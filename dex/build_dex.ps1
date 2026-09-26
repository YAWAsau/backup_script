# ============================================================
# HiddenApiUtil / NotificationUtil pure CLI classes.dex build script
# Usage: place in Android-DataBackup\dex\ folder, run in PowerShell:
#   .\build_dex.ps1
# ============================================================

param(
    [string]$JavaHome = "",
    [string]$SdkRoot = "",
    [switch]$Offline,
    [string]$AsciiBuildRoot = "",
    [switch]$NoDaemon
)

$ErrorActionPreference = "Stop"

function Publish-SpeedBackupDexFiles([object[]]$Pairs) {
    # Stage beside each destination; retain backups for pair rollback.
    $publishId = [Guid]::NewGuid().ToString("N")
    $entries = @()
    try {
        foreach ($pair in $Pairs) {
            $destination = [IO.Path]::GetFullPath($pair.Dst)
            $entry = [pscustomobject]@{
                Destination = $destination
                Temporary = $destination + "." + $publishId + ".tmp"
                Backup = $destination + "." + $publishId + ".bak"
                Existed = [IO.File]::Exists($destination)
                Committed = $false
                KeepBackup = $false
            }
            $entries += $entry
            Copy-Item -LiteralPath $pair.Src -Destination $entry.Temporary -ErrorAction Stop
            if ((Get-FileHash -LiteralPath $pair.Src -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $entry.Temporary -Algorithm SHA256).Hash) {
                throw "Staged build output hash mismatch: $destination"
            }
        }
        foreach ($entry in $entries) {
            if ($entry.Existed) {
                [IO.File]::Replace($entry.Temporary, $entry.Destination, $entry.Backup)
            } else {
                [IO.File]::Move($entry.Temporary, $entry.Destination)
            }
            $entry.Committed = $true
        }
    } catch {
        $publishFailure = $_
        for ($entryIndex = $entries.Count - 1; $entryIndex -ge 0; $entryIndex--) {
            $entry = $entries[$entryIndex]
            if (-not $entry.Committed) { continue }
            try {
                if ($entry.Existed) {
                    # PowerShell converts a null string argument to an empty
                    # path on some hosts. Use our consumed staging path for
                    # the discarded new output; finally removes that file.
                    [IO.File]::Replace($entry.Backup, $entry.Destination, $entry.Temporary)
                } else {
                    [IO.File]::Delete($entry.Destination)
                }
            } catch {
                $entry.KeepBackup = $true
                Write-Warning "Build output rollback failed; preserved backup $($entry.Backup): $($_.Exception.Message)"
            }
        }
        throw $publishFailure
    } finally {
        foreach ($entry in $entries) {
            foreach ($candidate in @($entry.Temporary, $entry.Backup)) {
                if ($candidate -eq $entry.Backup -and $entry.KeepBackup) { continue }
                try { [IO.File]::Delete($candidate) }
                catch { Write-Warning "Build output temporary file retained: $candidate ($($_.Exception.Message))" }
            }
        }
    }
}

function Assert-SpeedBackupBuildTreeHasNoLinks([string]$Directory) {
    # Enumerate one directory at a time without following build-created links.
    $pendingDirectories = New-Object 'System.Collections.Generic.Stack[string]'
    $pendingDirectories.Push($Directory)
    while ($pendingDirectories.Count -gt 0) {
        $currentDirectory = $pendingDirectories.Pop()
        $currentEntry = Get-Item -LiteralPath $currentDirectory -Force -ErrorAction Stop
        if ($currentEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Build cleanup refused a linked directory: $currentDirectory"
        }
        foreach ($child in Get-ChildItem -LiteralPath $currentDirectory -Force -ErrorAction Stop) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Build cleanup refused a linked entry: $($child.FullName)"
            }
            if ($child.PSIsContainer) { $pendingDirectories.Push($child.FullName) }
        }
    }
}

function New-SpeedBackupDexStage([string]$RequestedRoot) {
    $explicitRoot = -not [string]::IsNullOrWhiteSpace($RequestedRoot)
    $candidates = @()
    if ($explicitRoot) {
        $candidates += $RequestedRoot
    } else {
        $candidates += [IO.Path]::GetTempPath()
        if ($env:SystemDrive -match '^[A-Za-z]:$') {
            $candidates += (Join-Path ($env:SystemDrive + "\") "sbdex")
        }
    }
    $failures = @()
    foreach ($candidate in $candidates) {
        try {
            $parent = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($candidate)
            # Reserve room for Gradle/AGP paths, even with legacy Windows tools.
            if ($parent -match '[^\x00-\x7F]' -or $parent.Length -gt 80) {
                throw "Build parent must be ASCII and at most 80 characters: $parent"
            }
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                if ($explicitRoot) { throw "ASCII build parent does not exist: $parent" }
                $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
            }
            $parentEntry = Get-Item -LiteralPath $parent -Force -ErrorAction Stop
            if ($parentEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Build parent is a linked directory: $parent"
            }
            # No -Force: a collision never reuses an existing build tree.
            $name = "sbdex-" + [Guid]::NewGuid().ToString("N").Substring(0,12)
            return (New-Item -ItemType Directory -Path (Join-Path $parent $name) -ErrorAction Stop)
        } catch {
            $failures += $_.Exception.Message
        }
    }
    throw ("No writable short ASCII build directory. Use -AsciiBuildRoot with an existing directory. " + ($failures -join "; "))
}

# Sync before ASCII staging. The stage carries generated version metadata.
$releaseSync = Join-Path (Split-Path -Parent $PSScriptRoot) 'sync_version.ps1'
if (Test-Path -LiteralPath $releaseSync -PathType Leaf) {
    & $releaseSync
} elseif (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'release-version.properties') -PathType Leaf)) {
    throw 'Missing VERSION synchronization metadata; use the FULL_SOURCE build entry.'
}

# AGP and Windows AIDL require ASCII paths. Stage deep ASCII projects too.
if ($env:OS -eq "Windows_NT" -and ($PSScriptRoot -match '[^\x00-\x7F]' -or $PSScriptRoot.Length -gt 100)) {
    $stageDir = New-SpeedBackupDexStage $AsciiBuildRoot
    $stageRoot = $stageDir.FullName
    $stageName = $stageDir.Name
    $stageParent = $stageDir.Parent.FullName

    function Copy-SpeedBackupDexSources([string]$From, [string]$To) {
        foreach ($entry in Get-ChildItem -LiteralPath $From -Force) {
            if ($entry.PSIsContainer -and $entry.Name -in @("build", ".gradle", ".git", ".idea")) { continue }
            if (-not $entry.PSIsContainer -and ($entry.Name -eq "local.properties" -or $entry.Name -match '^classes[0-9]*[.]dex$')) { continue }
            if ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw "Refusing a linked source entry in the temporary build: $($entry.FullName)"
            }
            $target = Join-Path $To $entry.Name
            if ($entry.PSIsContainer) {
                $null = New-Item -ItemType Directory -Path $target
                Copy-SpeedBackupDexSources $entry.FullName $target
            } else {
                Copy-Item -LiteralPath $entry.FullName -Destination $target
            }
        }
    }

    $stageExitCode = 1
    try {
        Copy-SpeedBackupDexSources $PSScriptRoot $stageRoot
        Write-Host "Unicode or long project path: building an isolated source copy at $stageRoot" -ForegroundColor Cyan
        $hostExe = Join-Path $PSHOME "powershell.exe"
        if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = Join-Path $PSHOME "pwsh.exe" }
        $stageArgs = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $stageRoot "build_dex.ps1"), "-NoDaemon")
        if (-not [string]::IsNullOrWhiteSpace($JavaHome)) {
            $stageArgs += @("-JavaHome", $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($JavaHome))
        }
        if (-not [string]::IsNullOrWhiteSpace($SdkRoot)) {
            $stageArgs += @("-SdkRoot", $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SdkRoot))
        }
        if ($Offline) { $stageArgs += "-Offline" }
        Push-Location -LiteralPath $stageRoot
        try {
            & $hostExe @stageArgs
            $stageExitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        if ($stageExitCode -eq 0) {
            # The child has already checked R8 output and all required Dex capabilities.
            $stagedDex = Join-Path $stageRoot "classes.dex"
            $stagedRelease = Join-Path $stageRoot "app/build/outputs/apk/release"
            $stagedApks = @(Get-ChildItem -LiteralPath $stagedRelease -Filter "*.apk" -File)
            if (-not (Test-Path -LiteralPath $stagedDex -PathType Leaf) -or $stagedApks.Count -ne 1) {
                throw "The isolated build did not produce the expected Dex and single release APK."
            }
            $finalRelease = Join-Path $PSScriptRoot "app/build/outputs/apk/release"
            $null = New-Item -ItemType Directory -Path $finalRelease -Force
            Publish-SpeedBackupDexFiles @(
                @{ Src = $stagedApks[0].FullName; Dst = (Join-Path $finalRelease $stagedApks[0].Name) },
                @{ Src = $stagedDex; Dst = (Join-Path $PSScriptRoot "classes.dex") }
            )
            $artifactSync = Join-Path (Split-Path -Parent $PSScriptRoot) 'sync_artifacts.ps1'
            if (Test-Path -LiteralPath $artifactSync -PathType Leaf) { & $artifactSync -Component Dex }
            Write-Host "Verified build outputs copied back to the original project:" -ForegroundColor Green
            Write-Host (Join-Path $PSScriptRoot "classes.dex")
            Write-Host (Join-Path $finalRelease $stagedApks[0].Name)
        }
    } finally {
        try {
            # Delete only the exact fresh directory created by this invocation.
            $resolvedStage = Get-Item -LiteralPath $stageRoot -Force -ErrorAction Stop
            if ($resolvedStage.FullName -ne $stageDir.FullName -or
                $resolvedStage.Parent.FullName.TrimEnd([char[]]"\/") -ne (Get-Item -LiteralPath $stageParent).FullName.TrimEnd([char[]]"\/") -or
                $resolvedStage.Name -ne $stageName -or
                ($resolvedStage.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                throw "Temporary build cleanup refused an unexpected path: $stageRoot"
            }
            Assert-SpeedBackupBuildTreeHasNoLinks $resolvedStage.FullName
            # Windows PowerShell 5.1 needs the extended path prefix for deep Gradle caches.
            $cleanupPath = "\\?\" + $resolvedStage.FullName
            if ($resolvedStage.FullName.StartsWith("\\")) {
                $cleanupPath = "\\?\UNC\" + $resolvedStage.FullName.TrimStart([char[]]"\")
            }
            Remove-Item -LiteralPath $cleanupPath -Recurse -Force -ErrorAction Stop
        } catch {
            # Retain the original build outcome and identify any leftover path.
            Write-Warning "Temporary build directory retained: $stageRoot ($($_.Exception.Message))"
        }
    }
    exit $stageExitCode
}

# ---- 1. Set JAVA_HOME (Android Studio bundled JDK) ----
if ([string]::IsNullOrWhiteSpace($JavaHome)) {
    # Gradle 8.2: prefer an installed JDK17; Studio's current JBR may be newer.
    $jdk17Home = Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE ".jdks") -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "17([.-]|$)" -and (Test-Path -LiteralPath (Join-Path $_.FullName "bin/java.exe")) } |
        Select-Object -First 1
    if ($jdk17Home) {
        $JavaHome = $jdk17Home.FullName
    } elseif (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $JavaHome = $env:JAVA_HOME
    } else {
        $JavaHome = "C:\Program Files\Android\Android Studio\jbr"
    }
}
$javaHome = $JavaHome
if (-not (Test-Path -LiteralPath $javaHome)) {
    Write-Host "JAVA_HOME not found: $javaHome" -ForegroundColor Red
    Write-Host "Edit the javaHome variable in this script to match your Android Studio JBR path" -ForegroundColor Yellow
    exit 1
}
$env:JAVA_HOME = $javaHome
Write-Host "JAVA_HOME = $env:JAVA_HOME" -ForegroundColor Green

# ---- 2. Write local.properties (SDK path) ----
if ([string]::IsNullOrWhiteSpace($SdkRoot)) {
    $SdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk"
}
$sdkPath = $SdkRoot
if (-not (Test-Path -LiteralPath $sdkPath)) {
    Write-Host "Android SDK not found: $sdkPath" -ForegroundColor Red
    Write-Host "Edit the sdkPath variable in this script to match your Android SDK path" -ForegroundColor Yellow
    exit 1
}
$sdkPathForward = $sdkPath.Replace("\", "/")
$localPropsPath = Join-Path $PSScriptRoot "local.properties"
$localPropsContent = "sdk.dir=" + $sdkPathForward
[System.IO.File]::WriteAllText($localPropsPath, $localPropsContent)
Write-Host "Wrote local.properties: $localPropsContent" -ForegroundColor Green

# ---- 3. Run Gradle build ----
Write-Host "Building :app:assembleRelease ..." -ForegroundColor Cyan
$gradlewPath = Join-Path $PSScriptRoot "gradlew.bat"
Push-Location -LiteralPath $PSScriptRoot
try {
    $gradleBuildArgs = @(":app:assembleRelease", "--console=plain")
    if ($NoDaemon) { $gradleBuildArgs += "--no-daemon" }
    if ($Offline) { $gradleBuildArgs += "--offline" }
    & $gradlewPath @gradleBuildArgs
    $gradleExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($gradleExitCode -ne 0) {
    Write-Host "Build failed, see errors above" -ForegroundColor Red
    exit 1
}

# ---- 4. Extract classes.dex from the release APK ----
$releaseDir = [System.IO.Path]::Combine($PSScriptRoot, "app", "build", "outputs", "apk", "release")
$releaseApk = Get-ChildItem -LiteralPath $releaseDir -Filter "*.apk" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $releaseApk) {
    Write-Host "Release APK not found in: $releaseDir" -ForegroundColor Red
    exit 1
}

# Read only the single CLI Dex entry; preserve prior extraction/build outputs.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$outputDex = Join-Path $PSScriptRoot "classes.dex"
$releaseArchive = [System.IO.Compression.ZipFile]::OpenRead($releaseApk.FullName)
try {
    $dexEntries = @($releaseArchive.Entries | Where-Object { $_.FullName -match "^classes[0-9]*[.]dex$" })
    if ($dexEntries.Count -ne 1 -or $dexEntries[0].FullName -ne "classes.dex") {
        throw "Expected a single classes.dex CLI artifact; found $($dexEntries.Count) entries"
    }
    $dexInputStream = $dexEntries[0].Open()
    try {
        $dexOutputStream = [System.IO.File]::Create($outputDex)
        try {
            $dexInputStream.CopyTo($dexOutputStream)
        } finally {
            $dexOutputStream.Dispose()
        }
    } finally {
        $dexInputStream.Dispose()
    }
} finally {
    $releaseArchive.Dispose()
}

# ---- 4b. Verify Dex-owned classes/capabilities survived R8; native caps are checked by dex_check ----
$dexBytes = [System.IO.File]::ReadAllBytes($outputDex)
$dexLatin1 = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetString($dexBytes)
$requiredDexStrings = @(
    "com/xayah/dex/WebDavDiscoveryUtil",
    "webdav.lan_discovery.v1",
    "webdav.speedbackup_identity.dex.v1",
    "appstate.run_results.v1",
    "appstate.result_files.v1",
    "appstate.ssaid.typed_result.v1",
    "dex.control_results.v1",
    "webdav.stream_result.v1",
    "webdav.chunk_write_coalesced.v1",
    "dex.result_contract.v1",
    "com/xayah/dex/AppStateLocalization",
    "appstate.localization.dex.v1",
    "appstate.localization.raw_plus_cn.v1",
    "webdav.cjk_put_replay_probe.v1",
    "webdav.managed_probe.nodot_temp.v1",
    "webdav.stream_probe.subdir.v1",
    "webdav.base_preflight.dex.v1",
    "webdav.directory_ensure.dex.v1",
    "webdav.options_preflight.dex.v1",
    "webdav.prepare_dirs_full_timing.dex.v1",
    "dex.root_unified_daemon.v1",
    "webdav.deep_policy_table.dex.v1",
    "com/xayah/dex/SpeedBackupRootDaemon",
    "ensurebaserel",
    "ensuredirrel",
    "optionspreflightrel",
    "dex.cchelper.glossary.v1",
    "dex.cchelper.table_refresh.v1",
    "dex.cchelper.zh_tw_polish.v1",
    "dex.cchelper.repeat_merge_fix.v1",
    "CCUTIL_SELFTEST_OK cchelper.table_refresh.v1 zh_tw_polish.v1 repeat_merge_fix.v1",
    "dex.process_observer.taskstack_package_guard.v1",
    "PACKAGE_SCOPE_TRIGGER reason=taskstack-top-target",
    "kill-package-live-rescan-v1",
    "dex.cgroup_freezer.native_package_kill_live_rescan.v1",
    "native-kill-package-pre-force-stop",
    "native-kill-package-post-force-stop",
    "dex.display_power.root_daemon.v1"
)
foreach ($needle in $requiredDexStrings) {
    if (-not $dexLatin1.Contains($needle)) {
        Write-Host "Dex verify failed, missing: $needle" -ForegroundColor Red
        exit 1
    }
}
Write-Host "Dex verify: required CLI classes and Dex capabilities present (version strings diagnostic only)" -ForegroundColor Green
$artifactSync = Join-Path (Split-Path -Parent $PSScriptRoot) 'sync_artifacts.ps1'
if (Test-Path -LiteralPath $artifactSync -PathType Leaf) { & $artifactSync -Component Dex }

# ---- 5. No companion APK / no UI output in zero-UI build ----
Write-Host ""
Write-Host "===== Build complete =====" -ForegroundColor Green
Write-Host "Release APK used:" -ForegroundColor Green
Write-Host $releaseApk.FullName -ForegroundColor Green
Write-Host "Output dex:" -ForegroundColor Green
Write-Host $outputDex -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Push dex to device:" -ForegroundColor White
Write-Host "   adb push classes.dex /sdcard/classes.dex" -ForegroundColor White
Write-Host "2. On device, set classpath and test:" -ForegroundColor White
Write-Host "   export CLASSPATH=/sdcard/classes.dex" -ForegroundColor White
Write-Host "   app_process /system/bin com.xayah.dex.HiddenApiUtil help" -ForegroundColor White
