param(
    [int]$Api = 28,
    [string]$NdkVersion = '28.2.13676358',
    [string]$NdkRoot = '',
    [string]$OutDir = 'out_compat_generic4k',
    [string]$CgfreezerSource = '',
    [string]$KeycheckBinary = '',
    [ValidateSet(4096,16384)][int]$CgfreezerPageSize = 16384,
    [switch]$RequireKeycheck,
    [switch]$KeepObjects
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Build = Join-Path $ScriptDir 'build_all_windows.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $Build `
    -Api $Api `
    -NdkVersion $NdkVersion `
    -NdkRoot $NdkRoot `
    -OutDir $OutDir `
    -CgfreezerSource $CgfreezerSource `
    -KeycheckBinary $KeycheckBinary `
    -CompatGeneric4K `
    -SpeedscanPageSize 4096 `
    -CgfreezerPageSize $CgfreezerPageSize `
    -RequireKeycheck:$RequireKeycheck `
    -KeepObjects:$KeepObjects
exit $LASTEXITCODE
