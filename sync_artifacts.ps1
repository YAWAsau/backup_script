[CmdletBinding()]
param(
    [switch]$Check,
    [ValidateSet('All', 'Dex', 'Rust')][string]$Component = 'All'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'sync_version.ps1') -Check
$runtimePrefix = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'tools/tools.sh') -PathType Leaf) { 'tools/' } else { '' }
$artifacts = [ordered]@{ 'dex_check.sh' = ($runtimePrefix + 'dex_check.sh') }
if ($Component -in @('All', 'Dex')) { $artifacts['classes.dex'] = 'dex/classes.dex' }
if ($Component -in @('All', 'Rust')) { $artifacts['speednative'] = 'rust/out/speednative' }
$scriptPath = Join-Path $PSScriptRoot ($runtimePrefix + 'tools.sh')
$body = [IO.File]::ReadAllText($scriptPath)
foreach ($entry in $artifacts.GetEnumerator()) {
    $path = Join-Path $PSScriptRoot $entry.Value
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Build artifact missing: $path" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $pattern = '(?m)^' + [regex]::Escape($entry.Key) + ' [0-9a-f]{64}$'
    if ([regex]::Matches($body, $pattern).Count -ne 1) { throw "Missing or duplicate SHA row: $($entry.Key)" }
    $wanted = $entry.Key + ' ' + $hash
    if ($Check -and [regex]::Match($body, $pattern).Value -ne $wanted) { throw "Stale runtime SHA row: $($entry.Key)" }
    $body = [regex]::Replace($body, $pattern, $wanted)
}
if (-not $Check) {
    [IO.File]::WriteAllText($scriptPath, $body, [Text.UTF8Encoding]::new($false))
}
Write-Host "Runtime SHA table synchronized: $($artifacts.Keys -join ', ')"
