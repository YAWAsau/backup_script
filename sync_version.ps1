[CmdletBinding()]
param([switch]$Check)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$rootDir = $PSScriptRoot
$runtimePrefix = if (Test-Path -LiteralPath (Join-Path $rootDir 'tools/tools.sh') -PathType Leaf) { 'tools/' } else { '' }
$scriptRelative = $runtimePrefix + 'tools.sh'
$selfCheckRelative = $runtimePrefix + 'dex_check.sh'
$utf8 = New-Object System.Text.UTF8Encoding($false)
. (Join-Path $rootDir 'read_versions.ps1')
$versions = Read-SpeedBackupVersions $rootDir
$release = $versions['build']
$releaseNumber = [int]$release.Substring(1)
# APK requires a bounded integer; this is derived metadata, not the public version.
# The offset keeps this newer than the previously distributed versionCode 2742.
$apkCode = 100000 + $releaseNumber
$cargoVersion = "$releaseNumber.0.0"
$pending = [ordered]@{}
$pending['VERSION'] = "$release`n"
function Read-Source([string]$relative) {
    return [IO.File]::ReadAllText((Join-Path $rootDir $relative)).Replace("`r`n", "`n")
}
function Replace-One([string]$body, [string]$pattern, [string]$value) {
    $regex = New-Object Text.RegularExpressions.Regex($pattern)
    if ($regex.Matches($body).Count -ne 1) { throw "Version assignment missing or duplicated: $pattern" }
    return $regex.Replace($body, [Text.RegularExpressions.MatchEvaluator]{ param($m) $value })
}
$body = Read-Source $scriptRelative
# backup_version is a numeric updater timestamp; keep its ordering independent.
# Older FULL_SOURCE layouts still carry a separate build variable.
if ([regex]::IsMatch($body, '(?m)^speedbackup_patch_build=')) {
    $body = Replace-One $body '(?m)^speedbackup_patch_build="[^"]*"$' ('speedbackup_patch_build="' + $release + '"')
}
$body = Replace-One $body '(?m)^speedbackup_script_version="[^"]*"$' ('speedbackup_script_version="' + $versions['script'] + '"')
$pending[$scriptRelative] = $body
$body = Read-Source $selfCheckRelative
$body = Replace-One $body '(?m)^DEX_CHECK_VERSION="[^"]*"$' ('DEX_CHECK_VERSION="' + $versions['script'] + '"')
$body = Replace-One $body '(?m)^DEX_CHECK_BUILD="[^"]*"$' ('DEX_CHECK_BUILD="' + $release + '"')
$body = Replace-One $body '(?m)^SELFTEST_SCRIPT_VERSION=.*$' 'SELFTEST_SCRIPT_VERSION="${SELFTEST_SCRIPT_VERSION:-$DEX_CHECK_VERSION}"'
$body = Replace-One $body '(?m)^SPEEDBACKUP_PATCH_BUILD=.*$' 'SPEEDBACKUP_PATCH_BUILD="${SPEEDBACKUP_PATCH_BUILD:-$DEX_CHECK_BUILD}"'
$pending[$selfCheckRelative] = $body
$pending['dex/app/src/main/java/com/xayah/dex/DexBuildInfo.java'] = @"
package com.xayah.dex;

/** Generated from versions.properties by sync_version.ps1. */
public final class DexBuildInfo {
    public static final String VERSION = "$($versions['dex'])";
    public static final String PATCH_BUILD = "$release";
    public static final String BUILD_TAG = PATCH_BUILD;
    public static final String R_TAG = VERSION;
    public static final String VERSION_DISPLAY = VERSION + " build=" + PATCH_BUILD;
    private DexBuildInfo() {}
}
"@ + "`n"
$pending['dex/release-version.properties'] = "version=$($versions['dex'])`nbuild=$release`nversionCode=$apkCode`n"
$pending['rust/Cargo.toml'] = Replace-One (Read-Source 'rust/Cargo.toml') '(?m)^version = "[^"]+"$' ('version = "' + $cargoVersion + '"')
$pending['rust/Cargo.lock'] = Replace-One (Read-Source 'rust/Cargo.lock') '(?m)(?<=name = "speedbackup-native-rs"\n)version = "[^"]+"' ('version = "' + $cargoVersion + '"')
# SHA row follows the generated self-check script even on source-only version bumps.
$sha = [Security.Cryptography.SHA256]::Create()
try { $selfCheckHash = ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($pending[$selfCheckRelative])))).Replace('-','').ToLowerInvariant() }
finally { $sha.Dispose() }
$pending[$scriptRelative] = Replace-One $pending[$scriptRelative] '(?m)^dex_check\.sh [0-9a-f]{64}$' ('dex_check.sh ' + $selfCheckHash)
foreach ($entry in $pending.GetEnumerator()) {
    $path = Join-Path $rootDir $entry.Key
    $wanted = $entry.Value.Replace("`r`n", "`n")
    $current = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { '' }
    if ($current -ne $wanted) {
        if ($Check) { throw "Release version metadata is stale: $($entry.Key)" }
        [IO.File]::WriteAllText($path, $wanted, $utf8)
    }
}
Write-Host "Build: $release; script: $($versions['script']); Dex: $($versions['dex']) (APK code $apkCode; Cargo $cargoVersion)"
