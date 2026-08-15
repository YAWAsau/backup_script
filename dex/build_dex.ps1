# ============================================================
# HiddenApiUtil / NotificationUtil pure CLI classes.dex build script
# Usage: place in Android-DataBackup\dex\ folder, run in PowerShell:
#   .\build_dex.ps1
# ============================================================

param(
    [string]$JavaHome = "",
    [string]$SdkRoot = ""
)

$ErrorActionPreference = "Stop"

# ---- 1. Set JAVA_HOME (Android Studio bundled JDK) ----
if ([string]::IsNullOrWhiteSpace($JavaHome)) {
    $JavaHome = "C:\Program Files\Android\Android Studio\jbr"
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
& $gradlewPath ":app:assembleRelease"
if ($LASTEXITCODE -ne 0) {
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

$zipPath = Join-Path $PSScriptRoot "app-release.zip"
$extractPath = Join-Path $PSScriptRoot "extracted"

Copy-Item -LiteralPath $releaseApk.FullName -Destination $zipPath -Force
if (Test-Path -LiteralPath $extractPath) {
    Remove-Item -LiteralPath $extractPath -Recurse -Force
}
Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

$dexFile = Get-ChildItem -LiteralPath $extractPath -Recurse -Filter "classes.dex" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $dexFile) {
    $dexFile = Get-ChildItem -LiteralPath $extractPath -Recurse -Filter "*.dex" -File -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $dexFile) {
    Write-Host "No .dex file found after extraction" -ForegroundColor Red
    exit 1
}

$outputDex = Join-Path $PSScriptRoot "classes.dex"
Copy-Item -LiteralPath $dexFile.FullName -Destination $outputDex -Force
Remove-Item -LiteralPath $zipPath -Force

# ---- 4b. Verify required classes survived R8/shrinker ----
$dexBytes = [System.IO.File]::ReadAllBytes($outputDex)
$dexLatin1 = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetString($dexBytes)
$requiredDexStrings = @(
    "com/xayah/dex/AppStateLocalization",
    "appstate.localization.dex.v1",
    "appstate.localization.raw_plus_cn.v1",
    "webdav.cjk_put_replay_probe.v1",
    "v2.6.94-single-tools-unified-root-webdav-deep-hiddenapi-sync-webdav-eof-quiet",
    "webdav.managed_probe.nodot_temp.v1",
    "webdav.stream_probe.subdir.v1",
    "webdav.base_preflight.dex.v1",
    "webdav.directory_ensure.dex.v1",
    "webdav.options_preflight.dex.v1",
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
    "v2.6.151-display-timeout-daemon-session-native-package-kill-live-rescan-taskstack-package-guard-native-package-freeze-parent-control",
    "v24.20.14-7.66-630-display-timeout-daemon-session-r201-202607232022",
    "dex.process_observer.taskstack_package_guard.v1",
    "PACKAGE_SCOPE_TRIGGER reason=taskstack-top-target",
    "freeze-package-single-request-v1",
    "thaw-uid-emergency-v1",
    "daemon-parent-control-v1",
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
Write-Host "Dex verify: required SpeedBackup r201 display-timeout daemon session classes/capabilities present" -ForegroundColor Green

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
