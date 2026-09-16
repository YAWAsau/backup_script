param(
  [Parameter(Mandatory=$true)][string]$Ndk,
  [string]$Arch = "arm64",
  [int]$Api = 28,
  [string]$HostTag = "windows-x86_64"
)
$ErrorActionPreference = "Stop"
$env:CARGO_PROFILE_RELEASE_OPT_LEVEL = "z"
$env:CARGO_PROFILE_RELEASE_LTO = "true"
$env:CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1"
$env:CARGO_PROFILE_RELEASE_PANIC = "abort"
$env:CARGO_PROFILE_RELEASE_STRIP = "symbols"
if (!(Test-Path $Ndk)) { throw "NDK path not found: $Ndk" }
$toolchain = Join-Path $Ndk "toolchains/llvm/prebuilt/$HostTag/bin"
$strip = Join-Path $toolchain "llvm-strip.exe"
switch ($Arch) {
  "arm64" { $rustTarget="aarch64-linux-android"; $clang=Join-Path $toolchain "aarch64-linux-android$Api-clang.cmd"; $out="out/android-arm64" }
  "aarch64" { $rustTarget="aarch64-linux-android"; $clang=Join-Path $toolchain "aarch64-linux-android$Api-clang.cmd"; $out="out/android-arm64" }
  "x86_64" { $rustTarget="x86_64-linux-android"; $clang=Join-Path $toolchain "x86_64-linux-android$Api-clang.cmd"; $out="out/android-x86_64" }
  default { throw "unsupported arch: $Arch" }
}
New-Item -ItemType Directory -Force .cargo | Out-Null
@"
[target.$rustTarget]
linker = "$clang"

[build]
target = "$rustTarget"
"@ | Set-Content -Encoding ascii .cargo/config.toml
rustup target add $rustTarget | Out-Null
cargo build --release --bins --target $rustTarget
New-Item -ItemType Directory -Force $out | Out-Null
foreach ($b in @("eventwait","filewatch","netwatch","procwait","speedscan","uidexec","unixsock","cgfreezer")) {
  Copy-Item "target/$rustTarget/release/$b" "$out/$b" -Force
  if (Test-Path $strip) {
    & $strip --strip-all "$out/$b" 2>$null
    if ($LASTEXITCODE -ne 0) { & $strip "$out/$b" 2>$null }
  }
}
Push-Location $out
sha256sum eventwait filewatch netwatch procwait speedscan uidexec unixsock cgfreezer > SHA256SUMS.native-rust-r550
Pop-Location
Write-Host "built: rust/$out"
