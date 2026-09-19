# ============================================================
# HiddenApiUtil / NotificationUtil pure CLI classes.dex build script
# Usage: place in Android-DataBackup\dex\ folder, run in PowerShell:
#   .\build_dex.ps1
# ============================================================

param(
    [string]$JavaHome = "",
    [string]$SdkRoot = "",
    [switch]$Offline
)

$ErrorActionPreference = "Stop"

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
