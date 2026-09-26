[CmdletBinding()]
param(
    [string]$JavaHome = '',
    [string]$SdkRoot = '',
    [string]$Ndk = '',
    [switch]$Offline
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'sync_version.ps1')
$hostExe = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = Join-Path $PSHOME 'powershell.exe' }

$nativeArgs = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'rust/build.ps1'))
if ($Ndk) { $nativeArgs += @('-Ndk', $Ndk) }
if ($SdkRoot) { $nativeArgs += @('-Sdk', $SdkRoot) }
& $hostExe @nativeArgs
if ($LASTEXITCODE -ne 0) { throw "Native build failed: $LASTEXITCODE" }

$dexArgs = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'dex/build_dex.ps1'), '-NoDaemon')
if ($JavaHome) { $dexArgs += @('-JavaHome', $JavaHome) }
if ($SdkRoot) { $dexArgs += @('-SdkRoot', $SdkRoot) }
if ($Offline) { $dexArgs += '-Offline' }
& $hostExe @dexArgs
if ($LASTEXITCODE -ne 0) { throw "Dex build failed: $LASTEXITCODE" }

& (Join-Path $PSScriptRoot 'sync_artifacts.ps1')
& (Join-Path $PSScriptRoot 'sync_artifacts.ps1') -Check
Write-Host "Build complete: $([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'VERSION')).Trim())"
