[CmdletBinding()]
param(
    [string]$Python = 'python',
    [string]$Output = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageArgs = @('-X', 'utf8', (Join-Path $PSScriptRoot 'package_source.py'))
if ($Output) { $packageArgs += @('--output', $Output) }
& $Python @packageArgs
if ($LASTEXITCODE -ne 0) { throw 'Clean source packaging failed; see the message above.' }
