[CmdletBinding()]
param(
    [string]$Ndk,
    [string]$Sdk,
    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RequiredNdkVersion = '30.0.16248370' # Android NDK r30; API remains 28
$Api = 28
$RustTarget = 'aarch64-linux-android'
$ExpectedMachine = 'AArch64'
$ExpectedLoadAlign = 0x4000
$Bins = @('speednative')
$LegacyApplets = @('cgfreezer','eventwait','filewatch','netwatch','procwait','speedscan','uidexec','unixsock')

function Write-Step([string]$Text) {
    Write-Host "[BUILD] $Text" -ForegroundColor Cyan
}

function Require-Command([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        throw "Required command not found in PATH: $Name"
    }
    return $cmd.Source
}

function Resolve-AndroidSdk([string]$ExplicitSdk) {
    $candidates = @()
    if ($ExplicitSdk) { $candidates += $ExplicitSdk }
    if ($env:ANDROID_SDK_ROOT) { $candidates += $env:ANDROID_SDK_ROOT }
    if ($env:ANDROID_HOME) { $candidates += $env:ANDROID_HOME }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'Android SDK not found. Install Android Studio/SDK, set ANDROID_SDK_ROOT, or pass -Sdk <path>.'
}

function Resolve-Ndk([string]$ExplicitNdk, [string]$SdkRoot) {
    if ($ExplicitNdk) {
        if (-not (Test-Path -LiteralPath $ExplicitNdk -PathType Container)) {
            throw "NDK path not found: $ExplicitNdk"
        }
        $resolved = (Resolve-Path -LiteralPath $ExplicitNdk).Path
        $revision = Get-NdkRevision $resolved
        if ($revision -ne $RequiredNdkVersion) {
            throw "Wrong explicit NDK revision: $revision; required $RequiredNdkVersion (r30)"
        }
        return $resolved
    }

    $candidates = @()
    if ($env:ANDROID_NDK_HOME) { $candidates += $env:ANDROID_NDK_HOME }
    if ($env:ANDROID_NDK_ROOT) { $candidates += $env:ANDROID_NDK_ROOT }
    $candidates += (Join-Path $SdkRoot "ndk\$RequiredNdkVersion")

    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        try {
            $revision = Get-NdkRevision $resolved
            if ($revision -eq $RequiredNdkVersion) {
                return $resolved
            }
        } catch {
            # Ignore unrelated/broken NDK candidates and continue to the fixed SDK path.
        }
    }
    throw "Android NDK r30 ($RequiredNdkVersion) not found under $SdkRoot\ndk. Install it with Android Studio SDK Manager or pass -Ndk <path>."
}

function Get-NdkRevision([string]$NdkRoot) {
    $props = Join-Path $NdkRoot 'source.properties'
    if (-not (Test-Path -LiteralPath $props -PathType Leaf)) {
        throw "NDK source.properties missing: $props"
    }
    $line = Get-Content -LiteralPath $props | Where-Object { $_ -match '^Pkg\.Revision\s*=' } | Select-Object -First 1
    if (-not $line) {
        throw "Unable to read Pkg.Revision from $props"
    }
    return (($line -split '=', 2)[1]).Trim()
}

function Assert-Tool([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Name not found: $Path"
    }
}

function Assert-Elf([string]$Path, [string]$ReadElf) {
    $header = & $ReadElf -h $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "llvm-readelf -h failed for $Path"
    }
    if (-not ($header -match "Machine:\s+$ExpectedMachine")) {
        throw "Unexpected ELF machine for $Path; expected $ExpectedMachine"
    }
    if (-not ($header -match 'Type:\s+DYN')) {
        throw "Unexpected ELF type for $Path; expected DYN (PIE)"
    }

    $program = & $ReadElf -lW $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "llvm-readelf -lW failed for $Path"
    }

    $loadCount = 0
    foreach ($line in $program) {
        if ($line -match '^\s*LOAD\s+.*\s(0x[0-9A-Fa-f]+)\s*$') {
            $loadCount++
            $align = [Convert]::ToInt64($Matches[1].Substring(2), 16)
            if ($align -ne $ExpectedLoadAlign) {
                throw ("Invalid LOAD alignment for {0}: {1}; expected 0x4000 (16384)" -f $Path, $Matches[1])
            }
        }
    }
    if ($loadCount -eq 0) {
        throw "No LOAD program headers found in $Path"
    }
    $notes = & $ReadElf -n $Path 2>&1
    if ($LASTEXITCODE -ne 0 -or -not ($notes -match '1c 00 00 00 72 33 30 00')) {
        throw "Expected Android API28 / NDK r30 build note missing: $Path"
    }
}

$OriginalLocation = Get-Location
$OriginalEnv = @{
    CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
    CARGO_TARGET_AARCH64_LINUX_ANDROID_AR = $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_AR
    CC_aarch64_linux_android = $env:CC_aarch64_linux_android
    AR_aarch64_linux_android = $env:AR_aarch64_linux_android
    RUSTFLAGS = $env:RUSTFLAGS
    CARGO_PROFILE_RELEASE_OPT_LEVEL = $env:CARGO_PROFILE_RELEASE_OPT_LEVEL
    CARGO_PROFILE_RELEASE_LTO = $env:CARGO_PROFILE_RELEASE_LTO
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = $env:CARGO_PROFILE_RELEASE_CODEGEN_UNITS
    CARGO_PROFILE_RELEASE_PANIC = $env:CARGO_PROFILE_RELEASE_PANIC
    CARGO_PROFILE_RELEASE_STRIP = $env:CARGO_PROFILE_RELEASE_STRIP
    CARGO_TARGET_DIR = $env:CARGO_TARGET_DIR
}

try {
    Set-Location -LiteralPath $PSScriptRoot

    Write-Step 'Checking host tools'
    $null = Require-Command 'cargo'
    $null = Require-Command 'rustc'
    $null = Require-Command 'rustup'

    $SdkRoot = Resolve-AndroidSdk $Sdk
    $NdkRoot = Resolve-Ndk $Ndk $SdkRoot
    $NdkRevision = Get-NdkRevision $NdkRoot
    if ($NdkRevision -ne $RequiredNdkVersion) {
        throw "Wrong NDK revision: $NdkRevision; required $RequiredNdkVersion (r30)"
    }

    $HostTag = 'windows-x86_64'
    $Toolchain = Join-Path $NdkRoot "toolchains\llvm\prebuilt\$HostTag\bin"
    $Clang = Join-Path $Toolchain "aarch64-linux-android$Api-clang.cmd"
    $LlvmAr = Join-Path $Toolchain 'llvm-ar.exe'
    $Strip = Join-Path $Toolchain 'llvm-strip.exe'
    $ReadElf = Join-Path $Toolchain 'llvm-readelf.exe'

    Assert-Tool $Clang 'Android clang'
    Assert-Tool $LlvmAr 'llvm-ar'
    Assert-Tool $Strip 'llvm-strip'
    Assert-Tool $ReadElf 'llvm-readelf'

    Write-Host "  SDK       : $SdkRoot"
    Write-Host "  NDK       : $NdkRoot"
    Write-Host "  NDK rev   : $NdkRevision (r30)"
    Write-Host "  API       : $Api"
    Write-Host "  target    : $RustTarget"
    Write-Host '  page size : 16384 (0x4000)'

    Write-Step "Ensuring Rust target $RustTarget"
    $installed = & rustup target list --installed
    if ($LASTEXITCODE -ne 0) { throw 'rustup target list failed' }
    if ($installed -notcontains $RustTarget) {
        & rustup target add $RustTarget
        if ($LASTEXITCODE -ne 0) { throw "rustup target add $RustTarget failed" }
    }

    $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $Clang
    $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_AR = $LlvmAr
    $env:CC_aarch64_linux_android = $Clang
    $env:AR_aarch64_linux_android = $LlvmAr
    $env:RUSTFLAGS = '-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384'
    $env:CARGO_PROFILE_RELEASE_OPT_LEVEL = 'z'
    $env:CARGO_PROFILE_RELEASE_LTO = 'true'
    $env:CARGO_PROFILE_RELEASE_CODEGEN_UNITS = '1'
    $env:CARGO_PROFILE_RELEASE_PANIC = 'abort'
    $env:CARGO_PROFILE_RELEASE_STRIP = 'symbols'

    # Keep Cargo intermediates outside the source tree. This preserves incremental
    # builds while keeping rust\out limited to final deliverables only.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $projectId = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($PSScriptRoot)))).Replace('-', '').Substring(0, 12)
    } finally { $sha.Dispose() }
    $cacheName = "SpeedBackup-cargo-$projectId-ndk30-api28"
    # -Clean requests a fresh build without deleting old source or build output.
    if ($Clean) { $cacheName += '-' + [Guid]::NewGuid().ToString('N') }
    $CargoTargetDir = Join-Path ([System.IO.Path]::GetTempPath()) $cacheName
    $env:CARGO_TARGET_DIR = $CargoTargetDir

    Write-Step 'Building all Android arm64 release binaries'
    & cargo build --locked --offline --release --bins --target $RustTarget
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed with exit code $LASTEXITCODE" }

    Write-Step 'Compiling Android tests (not executing them on the host)'
    & cargo test --locked --offline --no-run --bins --target $RustTarget
    if ($LASTEXITCODE -ne 0) { throw "cargo test compilation failed with exit code $LASTEXITCODE" }

    $ReleaseDir = Join-Path $CargoTargetDir "$RustTarget\release"
    $OutDir = Join-Path $PSScriptRoot 'out'
    $runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $StageDir = Join-Path $CargoTargetDir "validated-$runId"
    New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    Write-Step 'Stripping and validating ELF binaries'
    foreach ($bin in $Bins) {
        $source = Join-Path $ReleaseDir $bin
        $dest = Join-Path $StageDir $bin
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Expected Cargo output missing: $source"
        }

        Copy-Item -LiteralPath $source -Destination $dest -Force
        & $Strip --strip-all $dest
        if ($LASTEXITCODE -ne 0) { throw "llvm-strip failed for $bin" }
        Assert-Elf $dest $ReadElf
        Write-Host "  OK $bin" -ForegroundColor Green
    }

    # Preserve previous binaries and hashes; publish only after every ELF passed.
    $BackupDir = Join-Path $PSScriptRoot "out-history\$runId"
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    foreach ($name in ($Bins + $LegacyApplets + @('SHA256SUMS.txt', 'BUILD_INFO.json'))) {
        $previous = Join-Path $OutDir $name
        if (Test-Path -LiteralPath $previous -PathType Leaf) {
            Copy-Item -LiteralPath $previous -Destination (Join-Path $BackupDir $name)
        }
    }
    foreach ($bin in $Bins) {
        Copy-Item -LiteralPath (Join-Path $StageDir $bin) -Destination (Join-Path $OutDir $bin) -Force
    }

    # The old eight ELF files are retained in out-history; publish only one ELF.
    foreach ($name in $LegacyApplets) {
        $oldFile = Join-Path $OutDir $name
        if (Test-Path -LiteralPath $oldFile -PathType Leaf) {
            if (-not (Test-Path -LiteralPath (Join-Path $BackupDir $name))) { throw "Missing backup: $name" }
            Remove-Item -LiteralPath $oldFile
        }
    }

    Write-Step 'Writing SHA256SUMS.txt'
    $sumLines = foreach ($bin in $Bins) {
        $hash = (Get-FileHash -LiteralPath (Join-Path $OutDir $bin) -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $bin"
    }
    $sumPath = Join-Path $OutDir 'SHA256SUMS.txt'
    $sumLines | Set-Content -LiteralPath $sumPath -Encoding Ascii

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $info = [ordered]@{
        ndk = $NdkRevision; api = $Api; target = $RustTarget; pageSize = $ExpectedLoadAlign
        applets = $LegacyApplets; dispatch = 'argv0-symlinks-or-subcommand'
        rustc = (& rustc --version | Out-String).Trim()
        clang = (& $Clang --version | Out-String).Trim()
        androidTests = 'compiled, not executed'; previousOutput = $BackupDir
        sha256 = @($sumLines)
    }
    [IO.File]::WriteAllText((Join-Path $OutDir 'BUILD_INFO.json'), ($info | ConvertTo-Json -Depth 4) + "`n", $utf8)
    $toolsFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools.sh'
    if (Test-Path -LiteralPath $toolsFile -PathType Leaf) {
        $text = [IO.File]::ReadAllText($toolsFile)
        $table = [regex]::Match($text, "(?ms)^\tcat <<'SB_TOOL_SHA_TABLE'\r?\n.*?^SB_TOOL_SHA_TABLE\r?$")
        if (-not $table.Success) { throw 'Cannot find the runtime SHA table in tools.sh' }
        $updated = $table.Value
        foreach ($bin in $Bins) {
            $hash = (Get-FileHash -LiteralPath (Join-Path $OutDir $bin) -Algorithm SHA256).Hash.ToLowerInvariant()
            $pattern = '(?m)^' + [regex]::Escape($bin) + ' [0-9a-f]{64}(?=\r?$)'
            if ([regex]::Matches($updated, $pattern).Count -ne 1) { throw "Missing or duplicate SHA row: $bin" }
            $updated = [regex]::Replace($updated, $pattern, "$bin $hash")
        }
        Copy-Item -LiteralPath $toolsFile -Destination (Join-Path $BackupDir 'tools.sh')
        [IO.File]::WriteAllText($toolsFile, $text.Substring(0, $table.Index) + $updated + $text.Substring($table.Index + $table.Length), $utf8)
        Write-Step 'Updated native SHA rows in tools.sh'
    }

    Write-Host ''
    Write-Host '========== BUILD PASS ==========' -ForegroundColor Green
    Write-Host "Output: $OutDir"
    Write-Host "SHA256: $sumPath"
    Write-Host '================================' -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host '========== BUILD FAIL ==========' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host '================================' -ForegroundColor Red
    exit 1
}
finally {
    foreach ($name in $OriginalEnv.Keys) {
        $value = $OriginalEnv[$name]
        if ($null -eq $value) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        } else {
            Set-Item "Env:$name" $value
        }
    }
    Set-Location $OriginalLocation
}
