[CmdletBinding()]
param(
    [string]$JavaHome = '',
    [string]$SdkRoot = '',
    [string]$Ndk = '',
    [string]$SigningDir = '',
    [switch]$Offline
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& python -X utf8 (Join-Path $PSScriptRoot 'restore_upstream.py') --check
if ($LASTEXITCODE -ne 0) { throw 'Bundled upstream source integrity check failed.' }
& (Join-Path $PSScriptRoot 'sync_version.ps1')
$hostExe = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = Join-Path $PSHOME 'powershell.exe' }

# Pinned dependency metadata is shared by the native license screens.
& python -X utf8 (Join-Path $PSScriptRoot 'ci/generate_licenses.py') --check
if ($LASTEXITCODE -ne 0) { throw "License catalogue validation failed: $LASTEXITCODE" }

# The UI host has an independent version and signing identity. Embed before Rust compilation.
if (-not $JavaHome) { $JavaHome = $env:JAVA_HOME }
if (-not $JavaHome -or -not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))) { throw 'Set JAVA_HOME or -JavaHome to a JDK 21+ installation.' }
$env:JAVA_HOME = $JavaHome
if (-not $SigningDir) { $SigningDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.speedbackup/signing' }
$env:SPEEDBACKUP_SIGNING_DIR = [IO.Path]::GetFullPath($SigningDir)
& python -X utf8 (Join-Path $PSScriptRoot 'configure_signing.py') --directory $env:SPEEDBACKUP_SIGNING_DIR
if ($LASTEXITCODE -ne 0) { throw 'Developer signing identity setup failed.' }
if ($SdkRoot) { $env:ANDROID_HOME = $SdkRoot }
& python -X utf8 (Join-Path $PSScriptRoot 'webview/build.py')
if ($LASTEXITCODE -ne 0) { throw "Native APK build/verification failed: $LASTEXITCODE" }

$dexArgs = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'dex/build_dex.ps1'), '-NoDaemon')
if ($JavaHome) { $dexArgs += @('-JavaHome', $JavaHome) }
if ($SdkRoot) { $dexArgs += @('-SdkRoot', $SdkRoot) }
if ($Offline) { $dexArgs += '-Offline' }
& $hostExe @dexArgs
if ($LASTEXITCODE -ne 0) { throw "Dex build failed: $LASTEXITCODE" }

$nativeArgs = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'rust/build.ps1'))
if ($Ndk) { $nativeArgs += @('-Ndk', $Ndk) }
if ($SdkRoot) { $nativeArgs += @('-Sdk', $SdkRoot) }
& $hostExe @nativeArgs
if ($LASTEXITCODE -ne 0) { throw "Native build failed: $LASTEXITCODE" }

& (Join-Path $PSScriptRoot 'sync_artifacts.ps1')
& (Join-Path $PSScriptRoot 'sync_artifacts.ps1') -Check
Write-Host "Build complete: $([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'VERSION')).Trim())"
