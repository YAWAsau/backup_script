param(
    [Parameter(Mandatory=$true)][string]$Readelf,
    [Parameter(Mandatory=$true)][string]$Binary,
    [ValidateSet('dynamic','static-nolibc')][string]$Mode = 'dynamic',
    [string]$ExpectedLoadAlign = '0x4000',
    [string]$ExpectedRelroEndAlign = '0x4000'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Fail([string]$Message) {
    Write-Host "[VERIFY-ERROR] $Message"
    exit 1
}

function Normalize-Hex([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'any' }
    $v = $Value.Trim().ToLowerInvariant()
    if ($v -eq 'any') { return 'any' }
    if ($v -match '^0x[0-9a-f]+$') { return $v }
    if ($v -match '^[0-9]+$') { return ('0x{0:x}' -f [UInt64]$v) }
    Fail "bad alignment value: $Value"
}

function Parse-Hex64([string]$Value) {
    $v = $Value.Trim()
    if ($v.StartsWith('0x')) { $v = $v.Substring(2) }
    return [Convert]::ToUInt64($v, 16)
}

function Get-ProgramHeaderAlign([string]$Line) {
    $fields = @($Line -split '\s+' | Where-Object { $_ -ne '' })
    if ($fields.Count -lt 7) { Fail "cannot parse program header alignment: $Line" }
    # llvm-readelf -lW layout is:
    # Type Offset VirtAddr PhysAddr FileSiz MemSiz Flg Align
    # The Flg column may be one token (R/RW) or two tokens (R E), so the
    # alignment is the LAST token, not a fixed column such as fields[7].
    return Normalize-Hex $fields[$fields.Count - 1]
}

function Test-LoadAligned {
    param([object[]]$ProgramHeaders, [string]$ExpectedAlign)
    if ($ExpectedAlign -eq 'any') { return }
    $badLoads = @()
    foreach ($line in $ProgramHeaders) {
        $s = $line.ToString()
        if ($s -match '^\s*LOAD\s') {
            $align = Get-ProgramHeaderAlign $s
            if ($align -ne $ExpectedAlign) { $badLoads += $s }
        }
    }
    if ($badLoads.Count -gt 0) {
        Write-Host "Bad LOAD alignment lines:"
        $badLoads | ForEach-Object { Write-Host $_ }
        Fail "all LOAD segment alignments must be $ExpectedAlign"
    }
}

function Test-RelroAligned {
    param([object[]]$ProgramHeaders, [string]$ExpectedAlign)
    if ($ExpectedAlign -eq 'any') { return }
    $relroLines = @($ProgramHeaders | Where-Object { $_.ToString() -match '^\s*GNU_RELRO\s' })
    if ($relroLines.Count -eq 0) {
        Write-Host '[VERIFY-WARN] GNU_RELRO segment not found'
        return
    }
    $alignValue = Parse-Hex64 $ExpectedAlign
    foreach ($relro in $relroLines) {
        $line = $relro.ToString()
        $fields = @($line -split '\s+' | Where-Object { $_ -ne '' })
        if ($fields.Count -lt 6) { Fail "cannot parse GNU_RELRO program header: $line" }
        # llvm-readelf -lW layout:
        # Type Offset VirtAddr PhysAddr FileSiz MemSiz Flg Align
        $vaddr = Parse-Hex64 $fields[2]
        $memsz = Parse-Hex64 $fields[5]
        $relroSegmentAlign = Get-ProgramHeaderAlign $line
        $relroEnd = $vaddr + $memsz
        if (($relroEnd % $alignValue) -ne 0) {
            $endHex = ('0x{0:X}' -f $relroEnd)
            Fail "$Binary : GNU_RELRO end $endHex is not aligned to $ExpectedAlign. This can trigger old Android linker errors such as: can't enable GNU RELRO protection: Out of memory"
        }
    }
}

if (-not (Test-Path -LiteralPath $Readelf)) { Fail "llvm-readelf not found: $Readelf" }
if (-not (Test-Path -LiteralPath $Binary)) { Fail "binary not found: $Binary" }

$ExpectedLoadAlign = Normalize-Hex $ExpectedLoadAlign
$ExpectedRelroEndAlign = Normalize-Hex $ExpectedRelroEndAlign

$hdr = & $Readelf -h $Binary 2>&1
if ($LASTEXITCODE -ne 0) { $hdr | ForEach-Object { Write-Host $_ }; Fail "readelf -h failed" }
$typeLine = @($hdr | Select-String 'Type:' | Select-Object -First 1)
if ($typeLine.Count -lt 1) { Fail "ELF Type line missing" }
$typeText = $typeLine[0].Line

$phdr = & $Readelf -lW $Binary 2>&1
if ($LASTEXITCODE -ne 0) { $phdr | ForEach-Object { Write-Host $_ }; Fail "readelf -lW failed" }

Test-LoadAligned -ProgramHeaders $phdr -ExpectedAlign $ExpectedLoadAlign
Test-RelroAligned -ProgramHeaders $phdr -ExpectedAlign $ExpectedRelroEndAlign

$dyn = & $Readelf -d $Binary 2>&1
$dynRc = $LASTEXITCODE
$needed = @()
$libs = @()
if ($dynRc -eq 0) {
    $needed = @($dyn | Select-String 'NEEDED')
    foreach ($n in $needed) {
        if ($n.Line -match '\[([^\]]+)\]') { $libs += $Matches[1] }
    }
    $libs = @($libs | Sort-Object -Unique)
}

if ($Mode -eq 'dynamic') {
    if ($typeText -notmatch '\bDYN\b') { Write-Host $typeText; Fail "ELF Type must be DYN/PIE" }
    if (-not @($phdr | Select-String '/system/bin/linker64')) { Fail "INTERP must be /system/bin/linker64" }
    if ($dynRc -ne 0) { $dyn | ForEach-Object { Write-Host $_ }; Fail "readelf -d failed" }
    $allowed = @('libc.so', 'libdl.so')
    $missingLibc = -not ($libs -contains 'libc.so')
    $badLibs = @($libs | Where-Object { $allowed -notcontains $_ })
    if ($missingLibc -or $badLibs.Count -gt 0) {
        Write-Host "NEEDED entries:"
        if ($needed.Count -eq 0) { Write-Host "  <none>" } else { $needed | ForEach-Object { Write-Host $_.Line } }
        if ($missingLibc) { Fail "binary must depend on libc.so" }
        Fail ("binary has unexpected NEEDED dependencies: " + ($badLibs -join ', '))
    }
    Write-Host ("[VERIFY-OK] mode=dynamic Type=DYN INTERP=/system/bin/linker64 NEEDED=" + ($libs -join ',') + " LOAD_ALIGN=$ExpectedLoadAlign RELRO_END_ALIGN=$ExpectedRelroEndAlign")
    exit 0
}

if ($Mode -eq 'static-nolibc') {
    if ($typeText -notmatch '\bEXEC\b') { Write-Host $typeText; Fail "static no-libc binary must be ELF Type EXEC" }
    if (@($phdr | Select-String 'INTERP').Count -gt 0) { Fail "static no-libc binary must not have INTERP" }
    if ($needed.Count -gt 0) {
        Write-Host "NEEDED entries:"
        $needed | ForEach-Object { Write-Host $_.Line }
        Fail "static no-libc binary must not have NEEDED dependencies"
    }
    Write-Host "[VERIFY-OK] mode=static-nolibc Type=EXEC INTERP=<none> NEEDED=<none> LOAD_ALIGN=$ExpectedLoadAlign RELRO_END_ALIGN=$ExpectedRelroEndAlign"
    exit 0
}

Fail "unknown mode: $Mode"
