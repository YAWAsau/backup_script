# Strict reader shared by version synchronization and native build metadata.
# Does not modify files. Applet values are independent; no shared-version fallback.
function Read-SpeedBackupVersions([string]$RootDirectory) {
    $keys = @('build', 'script', 'dex', 'cgfreezer', 'eventwait', 'filewatch', 'netwatch', 'procwait', 'speedscan', 'uidexec', 'unixsock')
    $values = [ordered]@{}
    $path = Join-Path $RootDirectory 'versions.properties'
    foreach ($rawLine in [IO.File]::ReadAllLines($path)) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -cnotmatch '^([a-z]+)=(v[1-9][0-9]{2})$') { throw "Invalid version entry: $line" }
        $key, $value = $Matches[1], $Matches[2]
        if ($keys -cnotcontains $key) { throw "Unknown version component: $key" }
        if ($values.Contains($key)) { throw "Duplicate version component: $key" }
        $values[$key] = $value
    }
    foreach ($key in $keys) {
        if (-not $values.Contains($key)) { throw "Missing version component: $key" }
    }
    return $values
}
