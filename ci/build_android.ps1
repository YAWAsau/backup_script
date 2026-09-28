[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$rootDir = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $rootDir 'ci-output'
$null = New-Item -ItemType Directory -Path $outputDir -Force
Push-Location -LiteralPath $rootDir
try {
    $config = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') | ConvertFrom-Json
    & python (Join-Path $PSScriptRoot 'check_repository.py') check
    if ($LASTEXITCODE -ne 0) { throw 'Repository checks failed.' }

    $sdkRoot = $env:ANDROID_HOME
    if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_SDK_ROOT }
    if (-not $sdkRoot -or -not (Test-Path -LiteralPath $sdkRoot)) { throw 'Android SDK is missing on the runner.' }
    $sdkManager = Join-Path $sdkRoot 'cmdline-tools/latest/bin/sdkmanager.bat'
    if (-not (Test-Path -LiteralPath $sdkManager)) { throw "sdkmanager not found: $sdkManager" }
    $env:ANDROID_HOME = $sdkRoot
    $env:ANDROID_SDK_ROOT = $sdkRoot
    & $sdkManager --version
    if ($LASTEXITCODE -ne 0) { throw 'sdkmanager failed.' }
    1..100 | ForEach-Object { 'y' } | & $sdkManager --licenses
    if ($LASTEXITCODE -ne 0) { throw 'Android SDK license acceptance failed.' }
    & $sdkManager "platforms;android-$($config.compile_sdk)" "build-tools;$($config.build_tools)" "ndk;$($config.ndk)"
    if ($LASTEXITCODE -ne 0) { throw 'Android SDK/NDK installation failed.' }

    & rustup toolchain install $config.rust --profile minimal --target $config.rust_target
    if ($LASTEXITCODE -ne 0) { throw 'Pinned Rust installation failed.' }
    $env:RUSTUP_TOOLCHAIN = $config.rust
    & rustc --version
    if ($LASTEXITCODE -ne 0) { throw 'rustc failed.' }

    # New source layouts may provide generated component-version metadata.
    $syncVersion = Join-Path $rootDir 'sync_version.ps1'
    if (Test-Path -LiteralPath $syncVersion) {
        & pwsh -NoProfile -File $syncVersion -Check
        if ($LASTEXITCODE -ne 0) { throw 'Generated version metadata is out of sync.' }
    }

    & pwsh -NoProfile -File (Join-Path $rootDir 'dex/build_dex.ps1') -JavaHome $env:JAVA_HOME -SdkRoot $sdkRoot -NoDaemon
    if ($LASTEXITCODE -ne 0) { throw 'Dex build failed.' }
    & pwsh -NoProfile -File (Join-Path $rootDir 'rust/build.ps1') -Sdk $sdkRoot -Ndk (Join-Path $sdkRoot "ndk/$($config.ndk)")
    if ($LASTEXITCODE -ne 0) { throw 'Rust build failed.' }

    & python (Join-Path $PSScriptRoot 'check_repository.py') package
    if ($LASTEXITCODE -ne 0) { throw 'Artifact validation/packaging failed.' }
} finally {
    Pop-Location
}
