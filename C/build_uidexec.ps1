param(
    [string]$Source = "",
    [string]$OutDir = "",
    [string]$NdkPath = "",
    [switch]$PushToDevice,
    [int]$TestUid = -1
)

$ErrorActionPreference = "Stop"

function Step($s) { Write-Host "[STEP] $s" }
function Ok($s) { Write-Host "[OK] $s" }
function Warn($s) { Write-Host "[WARN] $s" }
function Fail($s) { Write-Host "[FAIL] $s" }
function Q([string]$p) { return '"' + $p.Replace('"','\"') + '"' }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Source)) { $Source = Join-Path $scriptDir "uidexec.c" }
$Source = [System.IO.Path]::GetFullPath($Source)
if (-not (Test-Path -LiteralPath $Source)) { throw "Source not found: $Source" }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $scriptDir "dist" }
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$logFile = Join-Path $OutDir "build_uidexec_static_api21_api28.log"
if (Test-Path -LiteralPath $logFile) { Remove-Item -LiteralPath $logFile -Force }

Step "Source: $Source"
Step "Output dir: $OutDir"

function Find-Ndk {
    param([string]$Given)
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Given)) { $candidates.Add($Given) }
    $candidates.Add("C:\Users\22995\AppData\Local\Android\Sdk\ndk\30.0.14904198")
    if ($env:ANDROID_NDK_HOME) { $candidates.Add($env:ANDROID_NDK_HOME) }
    if ($env:ANDROID_NDK_ROOT) { $candidates.Add($env:ANDROID_NDK_ROOT) }
    if ($env:ANDROID_HOME) {
        $ndkRoot = Join-Path $env:ANDROID_HOME "ndk"
        if (Test-Path $ndkRoot) {
            Get-ChildItem $ndkRoot -Directory | Sort-Object Name -Descending | ForEach-Object { $candidates.Add($_.FullName) }
        }
    }
    foreach ($n in $candidates) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $clang = Join-Path $n "toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
        if (Test-Path -LiteralPath $clang) { return [System.IO.Path]::GetFullPath($n) }
    }
    throw "Android NDK not found"
}

Step "Find Android NDK"
$Ndk = Find-Ndk $NdkPath
$bin = Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\bin"
$clang = Join-Path $bin "clang.exe"
$strip = Join-Path $bin "llvm-strip.exe"
Ok "NDK: $Ndk"
Ok "CC : $clang"

function Run-CmdLine {
    param([string]$Title, [string]$CmdLine)
    Add-Content -LiteralPath $logFile -Value ""
    Add-Content -LiteralPath $logFile -Value "==== $Title ===="
    Add-Content -LiteralPath $logFile -Value "COMMAND: $CmdLine"
    $full = "$CmdLine >> " + (Q $logFile) + " 2>>&1"
    cmd.exe /d /s /c $full | Out-Null
    return $LASTEXITCODE
}

function Build-OneApi {
    param([int]$Api)
    $target = "--target=aarch64-linux-android$Api"
    $staticOut = Join-Path $OutDir "uidexec-arm64-static-api$Api"
    $staticPieOut = Join-Path $OutDir "uidexec-arm64-static-pie-api$Api"
    $dynOut = Join-Path $OutDir "uidexec-arm64-dynamic-stripped-api$Api"

    foreach ($f in @($staticOut,$staticPieOut,$dynOut)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }

    Step "Build static arm64 uidexec API $Api (no PIE)"
    $cmd = (Q $clang) + " $target -O2 -Wall -Wextra -D_FILE_OFFSET_BITS=64 -static -o " + (Q $staticOut) + " " + (Q $Source)
    $rc = Run-CmdLine "static-api$Api-no-pie" $cmd
    if ($rc -eq 0 -and (Test-Path -LiteralPath $staticOut)) {
        if (Test-Path -LiteralPath $strip) { Run-CmdLine "strip-static-api$Api" ((Q $strip) + " -s " + (Q $staticOut)) | Out-Null }
        Ok "Static API $Api build success: $staticOut"
        return $staticOut
    }
    Fail "Static API $Api no PIE failed"

    Step "Build static arm64 uidexec API $Api (PIE attempt)"
    $cmd = (Q $clang) + " $target -O2 -fPIE -Wall -Wextra -D_FILE_OFFSET_BITS=64 -static -o " + (Q $staticPieOut) + " " + (Q $Source)
    $rc = Run-CmdLine "static-api$Api-pie" $cmd
    if ($rc -eq 0 -and (Test-Path -LiteralPath $staticPieOut)) {
        if (Test-Path -LiteralPath $strip) { Run-CmdLine "strip-static-pie-api$Api" ((Q $strip) + " -s " + (Q $staticPieOut)) | Out-Null }
        Ok "Static PIE API $Api build success: $staticPieOut"
        return $staticPieOut
    }
    Fail "Static API $Api PIE failed"

    Warn "Build dynamic stripped fallback API $Api"
    Step "Build dynamic stripped fallback API $Api"
    $cmd = (Q $clang) + " $target -O2 -fPIE -pie -Wall -Wextra -D_FILE_OFFSET_BITS=64 -o " + (Q $dynOut) + " " + (Q $Source)
    $rc = Run-CmdLine "dynamic-api$Api" $cmd
    if ($rc -eq 0 -and (Test-Path -LiteralPath $dynOut)) {
        if (Test-Path -LiteralPath $strip) { Run-CmdLine "strip-dynamic-api$Api" ((Q $strip) + " -s " + (Q $dynOut)) | Out-Null }
        Ok "Dynamic fallback API $Api build success: $dynOut"
        return $dynOut
    }
    Fail "Dynamic fallback API $Api failed"
    return ""
}

$out21 = Build-OneApi 21
$out28 = Build-OneApi 28

$final = Join-Path $OutDir "uidexec"
if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Force }
if (-not [string]::IsNullOrWhiteSpace($out21) -and (Test-Path -LiteralPath $out21)) {
    Copy-Item -LiteralPath $out21 -Destination $final -Force
    Ok "Selected output: $out21 -> $final"
} elseif (-not [string]::IsNullOrWhiteSpace($out28) -and (Test-Path -LiteralPath $out28)) {
    Copy-Item -LiteralPath $out28 -Destination $final -Force
    Ok "Selected output: $out28 -> $final"
} else {
    throw "All builds failed. See log: $logFile"
}

Ok "Build log: $logFile"

if ($PushToDevice) {
    Step "Push to device"
    & adb push $final /data/local/tmp/uidexec
    & adb shell su -c "chmod 755 /data/local/tmp/uidexec"
    & adb shell su -c "file /data/local/tmp/uidexec"
    & adb shell su -c "/data/local/tmp/uidexec 0 id"
    if ($TestUid -ge 0) { & adb shell su -c "/data/local/tmp/uidexec $TestUid id" }
}

Ok "Done"
