# ============================================================
# HiddenApiUtil / NotificationUtil classes.dex build script
# Usage: place in Android-DataBackup\dex\ folder, run in PowerShell:
#   .\build_dex.ps1
# ============================================================

$ErrorActionPreference = "Stop"

# ---- 1. Set JAVA_HOME (Android Studio bundled JDK) ----
$javaHome = "C:\Program Files\Android\Android Studio\jbr"
if (-not (Test-Path -LiteralPath $javaHome)) {
    Write-Host "JAVA_HOME not found: $javaHome" -ForegroundColor Red
    Write-Host "Edit the javaHome variable in this script to match your Android Studio JBR path" -ForegroundColor Yellow
    exit 1
}
$env:JAVA_HOME = $javaHome
Write-Host "JAVA_HOME = $env:JAVA_HOME" -ForegroundColor Green

# ---- 2. Write local.properties (SDK path) ----
$sdkPath = Join-Path $env:LOCALAPPDATA "Android\Sdk"
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

# ---- 5. No companion APK output in no-actions build ----
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
