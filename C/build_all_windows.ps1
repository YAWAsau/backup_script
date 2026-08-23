param(
    [int]$Api = 28,
    [string]$NdkVersion = '28.2.13676358',
    [string]$NdkRoot = '',
    [string]$OutDir = 'out',
    [string]$CgfreezerSource = '',
    [string]$KeycheckBinary = '',
    [ValidateSet(4096,16384)][int]$GenericPageSize = 16384,
    [ValidateSet(4096,16384)][int]$SpeedscanPageSize = 16384,
    [ValidateSet(4096,16384)][int]$CgfreezerPageSize = 16384,
    [switch]$CompatGeneric4K,
    [switch]$AllowLegacy16K,
    [switch]$RequireKeycheck,
    [switch]$KeepObjects
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

$LogPath = Join-Path $ScriptDir 'build_all_windows.log'
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }

function Log([string]$Message = '') {
    Write-Host $Message
    Add-Content -LiteralPath $LogPath -Value $Message -Encoding UTF8
}

function Fail([string]$Message) {
    Log "[ERROR] $Message"
    Log "[ERROR] build log saved: $LogPath"
    exit 1
}

function Run-Checked {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Exe,
        [Parameter(Mandatory=$true)][string[]]$ArgList
    )
    Log ''
    Log "[$Title] $Exe $($ArgList -join ' ')"
    if ($ArgList.Count -le 0) { Fail "$Title has empty argument list" }
    $output = & $Exe @ArgList 2>&1
    $rc = $LASTEXITCODE
    foreach ($line in $output) { Log ($line.ToString()) }
    if ($rc -ne 0) { Fail "$Title failed rc=$rc" }
}

function Find-SdkRoot() {
    if ($env:ANDROID_SDK_ROOT) { return $env:ANDROID_SDK_ROOT }
    if ($env:ANDROID_HOME) { return $env:ANDROID_HOME }
    return (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
}

function Need-File([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail "$Name not found: $Path" }
}

function Parse-Ndk-Major([string]$Revision) {
    if ($Revision -match '^(\d+)\.') { return [int]$Matches[1] }
    return 0
}

function Resolve-CgfreezerSource() {
    if (-not [string]::IsNullOrWhiteSpace($CgfreezerSource)) {
        $p = $CgfreezerSource
        if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $ScriptDir $p }
        return [System.IO.Path]::GetFullPath($p)
    }

    $canonical = Join-Path $ScriptDir 'cgfreezer.c'
    if (Test-Path -LiteralPath $canonical -PathType Leaf) { return $canonical }

    $candidates = @(Get-ChildItem -LiteralPath $ScriptDir -Filter 'cgfreezer_*.c' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)

    if ($candidates.Count -eq 1) { return $candidates[0].FullName }
    if ($candidates.Count -gt 1) {
        $names = ($candidates | ForEach-Object { $_.Name }) -join ', '
        Fail "Multiple cgfreezer sources found. Rename the intended source to cgfreezer.c or pass -CgfreezerSource explicitly. Candidates: $names"
    }

    return $canonical
}

function Page-Align-Hex([int]$PageSize) {
    if ($PageSize -eq 4096) { return '0x1000' }
    if ($PageSize -eq 16384) { return '0x4000' }
    Fail "unsupported page size: $PageSize"
}

function Ld-Flags-For-PageSize([int]$PageSize) {
    return @('-pie', '-Wl,--gc-sections', '-Wl,-z,relro,-z,now', '-Wl,--build-id=sha1', "-Wl,-z,max-page-size=$PageSize", "-Wl,-z,common-page-size=$PageSize")
}

$GenericDynamicTools = @('filewatch','procwait','eventwait','unixsock','netwatch','uidexec')
$SpeedscanTool = 'speedscan'
$CgfreezerTool = 'cgfreezer'

if ($CompatGeneric4K) {
    $GenericPageSize = 4096
    $SpeedscanPageSize = 4096
    if ($OutDir -eq 'out') { $OutDir = 'out_compat_generic4k' }
}

$genericAlignHex = Page-Align-Hex $GenericPageSize
$speedscanAlignHex = Page-Align-Hex $SpeedscanPageSize
$cgAlignHex = Page-Align-Hex $CgfreezerPageSize
$ndkMajor = Parse-Ndk-Major $NdkVersion

Log '============================================================'
Log 'SpeedBackup Android native tools builder'
Log 'native_c package: r416-run-tmpdir-clean-api28-relroguard'
Log 'ABI : arm64'
Log "API : $Api"
Log 'Minimum runtime baseline: Android 9 / API 28 when using the default -Api value'
Log "NDK : $NdkVersion"
Log "Generic dynamic tools: PIE / /system/bin/linker64 / libc.so / pageSize=$GenericPageSize / LOAD_ALIGN=$genericAlignHex / RELRO_END_ALIGN=$genericAlignHex"
Log "speedscan: source-driven build / libc.so / pageSize=$SpeedscanPageSize / LOAD_ALIGN=$speedscanAlignHex / RELRO_END_ALIGN=$speedscanAlignHex"
Log "cgfreezer: source-driven build / libc.so + libdl.so / pageSize=$CgfreezerPageSize / LOAD_ALIGN=$cgAlignHex / RELRO_END_ALIGN=$cgAlignHex"
Log 'keycheck: never rebuilt from no-libc source; optional known-good prebuilt copy only'
Log ('Generic tools: ' + ($GenericDynamicTools -join ' '))
Log ('Speedscan tool: ' + $SpeedscanTool)
Log '============================================================'

if ($GenericPageSize -eq 16384 -and $ndkMajor -gt 0 -and $ndkMajor -lt 28 -and -not $AllowLegacy16K) {
    Fail "16K generic build with NDK r$ndkMajor is blocked. Use NDK r28+ for reliable RELRO padding, or pass -CompatGeneric4K for old 4K devices. Override only for diagnostics with -AllowLegacy16K."
}
if ($SpeedscanPageSize -eq 16384 -and $ndkMajor -gt 0 -and $ndkMajor -lt 28 -and -not $AllowLegacy16K) {
    Fail "16K speedscan build with NDK r$ndkMajor is blocked by default. Use NDK r28+ for reliable RELRO padding, or pass -CompatGeneric4K for old 4K devices. Override only for diagnostics with -AllowLegacy16K."
}
if ($CgfreezerPageSize -eq 16384 -and $ndkMajor -gt 0 -and $ndkMajor -lt 28 -and -not $AllowLegacy16K) {
    Fail "16K cgfreezer build with NDK r$ndkMajor is blocked by default. Use NDK r28+ or override only for diagnostics with -AllowLegacy16K."
}

if (-not $NdkRoot) {
    $sdkRoot = Find-SdkRoot
    $NdkRoot = Join-Path $sdkRoot ("ndk\$NdkVersion")
}
if ($env:EVENT_TOOLS_NDK_ROOT) { $NdkRoot = $env:EVENT_TOOLS_NDK_ROOT }
if ($env:ANDROID_NDK_HOME) { $NdkRoot = $env:ANDROID_NDK_HOME }

$sourceProperties = Join-Path $NdkRoot 'source.properties'
Need-File $sourceProperties 'Android NDK source.properties'
$sourcePropsText = Get-Content -LiteralPath $sourceProperties -Raw
if ($sourcePropsText -notmatch [regex]::Escape("Pkg.Revision = $NdkVersion")) {
    Log $sourcePropsText
    Fail "NDK revision mismatch. Expected $NdkVersion at: $NdkRoot"
}

$toolchain = Join-Path $NdkRoot 'toolchains\llvm\prebuilt\windows-x86_64\bin'
$clang = Join-Path $toolchain 'clang.exe'
$strip = Join-Path $toolchain 'llvm-strip.exe'
$readelf = Join-Path $toolchain 'llvm-readelf.exe'
$target = "--target=aarch64-linux-android$Api"
$libDir = Join-Path $NdkRoot "toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib\aarch64-linux-android\$Api"
$libcSo = Join-Path $libDir 'libc.so'

Need-File $clang 'clang.exe'
Need-File $strip 'llvm-strip.exe'
Need-File $readelf 'llvm-readelf.exe'
Need-File $libcSo 'Android dynamic libc stub'
Need-File (Join-Path $ScriptDir 'verify_elf_dynamic16k.ps1') 'verify_elf_dynamic16k.ps1'
foreach ($tool in $GenericDynamicTools) { Need-File (Join-Path $ScriptDir "$tool.c") "$tool.c" }
Need-File (Join-Path $ScriptDir "$SpeedscanTool.c") "$SpeedscanTool.c"

$resolvedCgSource = Resolve-CgfreezerSource
Need-File $resolvedCgSource 'cgfreezer source'
Log "cgfreezer source: $resolvedCgSource"
Log '[INFO] Build script validates compilation, ABI, dynamic dependencies, LOAD alignment and GNU_RELRO end alignment.'
Log '[INFO] Runtime capability/version contracts belong to dex_check/release assembly, not this compiler.'

Log "Dynamic libc stub: $libcSo"
$outPath = Join-Path $ScriptDir $OutDir
$objPath = Join-Path $outPath 'obj'
if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outPath | Out-Null
New-Item -ItemType Directory -Force -Path $objPath | Out-Null

$commonCFlags = @($target, '-std=c11', '-Os', '-fvisibility=hidden', '-ffunction-sections', '-fdata-sections', '-fPIE', '-fno-lto', '-Wall', '-Wextra', '-Werror')
$genericLdFlags = Ld-Flags-For-PageSize $GenericPageSize
$speedscanLdFlags = Ld-Flags-For-PageSize $SpeedscanPageSize
$cgLdFlags = Ld-Flags-For-PageSize $CgfreezerPageSize
$verifyScript = Join-Path $ScriptDir 'verify_elf_dynamic16k.ps1'

foreach ($tool in $GenericDynamicTools) {
    $src = Join-Path $ScriptDir "$tool.c"
    $obj = Join-Path $objPath "$tool.o"
    $bin = Join-Path $outPath $tool
    $compileArgs = [string[]](@($target) + $commonCFlags[1..($commonCFlags.Count-1)] + @('-c', $src, '-o', $obj))
    $linkArgs = [string[]](@($target, $obj) + $genericLdFlags + @('-o', $bin))
    $stripArgs = [string[]]@('--strip-all', $bin)
    $verifyArgs = [string[]]@('-NoProfile','-ExecutionPolicy','Bypass','-File',$verifyScript,'-Readelf',$readelf,'-Binary',$bin,'-Mode','dynamic','-ExpectedLoadAlign',$genericAlignHex,'-ExpectedRelroEndAlign',$genericAlignHex)
    Run-Checked -Title "$tool compile" -Exe $clang -ArgList $compileArgs
    Run-Checked -Title "$tool link dynamic PIE" -Exe $clang -ArgList $linkArgs
    Run-Checked -Title "$tool strip" -Exe $strip -ArgList $stripArgs
    Run-Checked -Title "$tool verify dynamic" -Exe 'powershell' -ArgList $verifyArgs
    Log "[OK] $tool"
}


# speedscan is a normal dynamic PIE Android CLI and must be built with the same
# RELRO-end guard as the other native tools. It is intentionally one-shot; this
# build script only validates ELF/linker contracts, not runtime command output.
$speedscanSrc = Join-Path $ScriptDir "$SpeedscanTool.c"
$speedscanObj = Join-Path $objPath "$SpeedscanTool.o"
$speedscanBin = Join-Path $outPath $SpeedscanTool
$speedscanCompileArgs = [string[]](@($target) + $commonCFlags[1..($commonCFlags.Count-1)] + @('-c', $speedscanSrc, '-o', $speedscanObj))
$speedscanLinkArgs = [string[]](@($target, $speedscanObj) + $speedscanLdFlags + @('-o', $speedscanBin))
$speedscanStripArgs = [string[]]@('--strip-all', $speedscanBin)
$speedscanVerifyArgs = [string[]]@('-NoProfile','-ExecutionPolicy','Bypass','-File',$verifyScript,'-Readelf',$readelf,'-Binary',$speedscanBin,'-Mode','dynamic','-ExpectedLoadAlign',$speedscanAlignHex,'-ExpectedRelroEndAlign',$speedscanAlignHex)
Run-Checked -Title 'speedscan compile' -Exe $clang -ArgList $speedscanCompileArgs
Run-Checked -Title 'speedscan link dynamic PIE' -Exe $clang -ArgList $speedscanLinkArgs
Run-Checked -Title 'speedscan strip' -Exe $strip -ArgList $speedscanStripArgs
Run-Checked -Title 'speedscan verify dynamic' -Exe 'powershell' -ArgList $speedscanVerifyArgs
Log '[OK] speedscan compiled; ELF/dependency/alignment contract passed'

# cgfreezer requires libdl for optional dlopen/dlsym runtime support; no version/capability token is pinned here.
$cgObj = Join-Path $objPath 'cgfreezer.o'
$cgBin = Join-Path $outPath 'cgfreezer'
$cgCompileArgs = [string[]](@($target) + $commonCFlags[1..($commonCFlags.Count-1)] + @('-O2', '-c', $resolvedCgSource, '-o', $cgObj))
$cgLinkArgs = [string[]](@($target, $cgObj) + $cgLdFlags + @('-ldl', '-o', $cgBin))
$cgStripArgs = [string[]]@('--strip-unneeded', $cgBin)
$cgVerifyArgs = [string[]]@('-NoProfile','-ExecutionPolicy','Bypass','-File',$verifyScript,'-Readelf',$readelf,'-Binary',$cgBin,'-Mode','dynamic','-ExpectedLoadAlign',$cgAlignHex,'-ExpectedRelroEndAlign',$cgAlignHex)
Run-Checked -Title 'cgfreezer compile' -Exe $clang -ArgList $cgCompileArgs
Run-Checked -Title 'cgfreezer link dynamic PIE + libdl' -Exe $clang -ArgList $cgLinkArgs
Run-Checked -Title 'cgfreezer strip' -Exe $strip -ArgList $cgStripArgs
Run-Checked -Title 'cgfreezer verify dynamic' -Exe 'powershell' -ArgList $cgVerifyArgs

$cgDynamic = & $readelf -dW $cgBin 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Fail 'cgfreezer llvm-readelf -dW failed' }
if ($cgDynamic -notmatch 'Shared library:\s*\[libc\.so\]') { Fail 'cgfreezer NEEDED libc.so missing' }
if ($cgDynamic -notmatch 'Shared library:\s*\[libdl\.so\]') { Fail 'cgfreezer NEEDED libdl.so missing' }
Log '[OK] cgfreezer compiled; ELF/dependency/alignment contract passed'

$builtTools = New-Object System.Collections.Generic.List[string]
foreach ($tool in $GenericDynamicTools) { $builtTools.Add($tool) }
$builtTools.Add('speedscan')
$builtTools.Add('cgfreezer')

# The r186 no-libc keycheck rewrite is intentionally forbidden here.
# Only copy a known-good legacy libc/stdout keycheck binary when explicitly supplied,
# or when a prebuilt file named "keycheck" already exists beside this script.
$resolvedKeycheck = ''
if (-not [string]::IsNullOrWhiteSpace($KeycheckBinary)) {
    $resolvedKeycheck = $KeycheckBinary
    if (-not [System.IO.Path]::IsPathRooted($resolvedKeycheck)) { $resolvedKeycheck = Join-Path $ScriptDir $resolvedKeycheck }
    $resolvedKeycheck = [System.IO.Path]::GetFullPath($resolvedKeycheck)
} else {
    $candidate = Join-Path $ScriptDir 'keycheck'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $resolvedKeycheck = $candidate }
}

if (-not [string]::IsNullOrWhiteSpace($resolvedKeycheck)) {
    Need-File $resolvedKeycheck 'known-good legacy libc/stdout keycheck binary'
    $keycheckOut = Join-Path $outPath 'keycheck'
    Copy-Item -LiteralPath $resolvedKeycheck -Destination $keycheckOut -Force
    $keycheckVerifyArgs = [string[]]@('-NoProfile','-ExecutionPolicy','Bypass','-File',$verifyScript,'-Readelf',$readelf,'-Binary',$keycheckOut,'-Mode','dynamic','-ExpectedLoadAlign','any','-ExpectedRelroEndAlign','any')
    Run-Checked -Title 'keycheck prebuilt verify dynamic' -Exe 'powershell' -ArgList $keycheckVerifyArgs
    Log '[OK] copied known-good legacy libc/stdout keycheck; no keycheck source was compiled'
    $builtTools.Add('keycheck')
} elseif ($RequireKeycheck) {
    Fail 'RequireKeycheck was specified, but no -KeycheckBinary and no prebuilt .\keycheck was found. The obsolete keycheck_exit_code.c will not be compiled.'
} else {
    Log '[INFO] keycheck omitted. Runtime must keep its existing known-good legacy libc/stdout keycheck.'
}

if (-not $KeepObjects) {
    Remove-Item -LiteralPath $objPath -Recurse -Force -ErrorAction SilentlyContinue
    Log '[OK] cleaned intermediate object directory out\obj'
} else {
    Log '[INFO] kept intermediate objects under out\obj because -KeepObjects was used'
}

$shaLines = foreach ($tool in $builtTools) {
    $bin = Join-Path $outPath $tool
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $bin).Hash.ToLowerInvariant()
    "$hash  $tool"
}
$shaPath = Join-Path $outPath 'SHA256SUMS.txt'
[System.IO.File]::WriteAllLines($shaPath, $shaLines, [System.Text.Encoding]::ASCII)

Log ''
Log 'Build complete:'
foreach ($tool in $builtTools) { Log ('  ' + (Join-Path $outPath $tool)) }
Log ('  ' + $shaPath)
Log ''
Log 'Verification expected:'
Log "  Generic dynamic tools: Type=DYN, INTERP=/system/bin/linker64, NEEDED libc.so, LOAD alignment=$genericAlignHex, GNU_RELRO end alignment=$genericAlignHex"
Log "  speedscan: Type=DYN, INTERP=/system/bin/linker64, NEEDED libc.so, LOAD alignment=$speedscanAlignHex, GNU_RELRO end alignment=$speedscanAlignHex"
Log "  cgfreezer: Type=DYN, NEEDED libc.so + libdl.so, LOAD alignment=$cgAlignHex, GNU_RELRO end alignment=$cgAlignHex"
Log '  keycheck: optional prebuilt only; never compiled from the obsolete no-libc source'
Log ''
Log 'Recommended builds:'
Log '  Normal 16K-safe build: powershell -ExecutionPolicy Bypass -File .\build_all_windows.ps1'
Log '  Old-device generic-helper/speedscan compat: powershell -ExecutionPolicy Bypass -File .\build_compat_generic4k_windows.ps1'
Log ''
Log 'Phone quick test:'
Log '  adb push out\speedscan /data/local/tmp/'
Log '  adb push out\cgfreezer /data/local/tmp/'
Log '  adb shell su -c "chmod 755 /data/local/tmp/speedscan /data/local/tmp/cgfreezer"'
Log '  adb shell su -c "/data/local/tmp/speedscan version"'
Log '  adb shell su -c "/data/local/tmp/cgfreezer HELLO"'
