@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "API=23"
set "NDK_VERSION=25.2.9519653"
rem Build every native binary shipped in this folder.
set "TOOLS=filewatch propwait procwait unixsock netwatch uidexec"

echo ============================================================
echo Android native tools builder
echo ABI : arm64
echo API : %API%
echo NDK : r25c (%NDK_VERSION%)
echo Type: dynamic PIE / /system/bin/linker64 / libc.so+libdl.so allowed / 16 KB aligned
echo Tools: %TOOLS%
echo ============================================================

set "SDK_ROOT="
if defined ANDROID_SDK_ROOT set "SDK_ROOT=%ANDROID_SDK_ROOT%"
if not defined SDK_ROOT if defined ANDROID_HOME set "SDK_ROOT=%ANDROID_HOME%"
if not defined SDK_ROOT set "SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"

set "NDK_ROOT=%SDK_ROOT%\ndk\%NDK_VERSION%"
if defined EVENT_TOOLS_NDK_ROOT set "NDK_ROOT=%EVENT_TOOLS_NDK_ROOT%"
if defined ANDROID_NDK_HOME set "NDK_ROOT=%ANDROID_NDK_HOME%"

if not exist "%NDK_ROOT%\source.properties" (
    echo [ERROR] Required Android NDK r25c was not found:
    echo   %NDK_ROOT%
    echo.
    echo Install:
    echo   sdkmanager "ndk;%NDK_VERSION%"
    echo.
    echo Or set one of:
    echo   set EVENT_TOOLS_NDK_ROOT=D:\Android\android-ndk-r25c
    echo   set ANDROID_NDK_HOME=D:\Android\android-ndk-r25c
    exit /b 1
)

findstr /C:"Pkg.Revision = %NDK_VERSION%" "%NDK_ROOT%\source.properties" >nul
if errorlevel 1 (
    echo [ERROR] NDK is not exactly r25c %NDK_VERSION%:
    type "%NDK_ROOT%\source.properties"
    exit /b 1
)

set "TOOLCHAIN=%NDK_ROOT%\toolchains\llvm\prebuilt\windows-x86_64\bin"
set "CLANG=%TOOLCHAIN%\clang.exe"
set "STRIP=%TOOLCHAIN%\llvm-strip.exe"
set "READELF=%TOOLCHAIN%\llvm-readelf.exe"
set "TARGET=--target=aarch64-linux-android%API%"
set "LIB_DIR=%NDK_ROOT%\toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib\aarch64-linux-android\%API%"
set "LIBC_SO=%LIB_DIR%\libc.so"

if not exist "%CLANG%" (
    echo [ERROR] clang.exe not found:
    echo   %CLANG%
    exit /b 1
)

if not exist "%STRIP%" (
    echo [ERROR] llvm-strip.exe not found:
    echo   %STRIP%
    exit /b 1
)

if not exist "%READELF%" (
    echo [ERROR] llvm-readelf.exe not found:
    echo   %READELF%
    exit /b 1
)

if not exist "%LIBC_SO%" (
    echo [ERROR] Android dynamic libc stub not found:
    echo   %LIBC_SO%
    echo.
    echo Existing API library layout:
    dir /b "%NDK_ROOT%\toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib\aarch64-linux-android" 2>nul
    exit /b 1
)

for %%T in (%TOOLS%) do (
    if not exist "%%T.c" (
        echo [ERROR] Missing source: %%T.c
        exit /b 1
    )
)

echo Dynamic libc stub:
echo   %LIBC_SO%

echo Checking dynamic bionic property wait symbols for propwait...
"%READELF%" --dyn-syms "%LIBC_SO%" | findstr /C:"__system_property_area_serial" >nul
if errorlevel 1 (
    echo [ERROR] libc.so stub does not export __system_property_area_serial for API %API%.
    exit /b 1
)
"%READELF%" --dyn-syms "%LIBC_SO%" | findstr /C:"__system_property_wait_any" >nul
if errorlevel 1 (
    echo [ERROR] libc.so stub does not export __system_property_wait_any for API %API%.
    exit /b 1
)
echo [OK] Dynamic property wait symbols found.

if not exist "out" mkdir "out"
for %%T in (%TOOLS%) do del /q "out\%%T" "out\%%T.o" 2>nul
del /q "out\SHA256SUMS.txt" 2>nul

set "CFLAGS=-std=c11 -Os -fvisibility=hidden -ffunction-sections -fdata-sections -fPIE -Wall -Wextra -Werror"
set "LDFLAGS=-pie -Wl,--gc-sections -Wl,-z,relro,-z,now -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"

for %%T in (%TOOLS%) do (
    echo.
    echo [%%T] Compiling...
    "%CLANG%" %TARGET% %CFLAGS% -c "%%T.c" -o "out\%%T.o"
    if errorlevel 1 exit /b 1

    echo [%%T] Linking dynamic PIE executable...
    "%CLANG%" %TARGET% "out\%%T.o" %LDFLAGS% -o "out\%%T"
    if errorlevel 1 exit /b 1

    echo [%%T] Stripping...
    "%STRIP%" --strip-all "out\%%T"
    if errorlevel 1 exit /b 1

    echo [%%T] Verifying ELF DYN PIE...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify_elf_dynamic16k.ps1" -Readelf "%READELF%" -Binary "out\%%T"
    if errorlevel 1 (
        echo [ERROR] %%T ELF verification failed.
        exit /b 1
    )

    echo [OK] %%T
)

del /q "out\*.o" 2>nul

echo.
echo Writing SHA256SUMS.txt...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$names='%TOOLS%'.Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries); $lines=foreach($n in $names){$h=(Get-FileHash -Algorithm SHA256 -LiteralPath ('out\'+$n)).Hash.ToLowerInvariant(); $h+'  '+$n}; [System.IO.File]::WriteAllLines((Join-Path (Get-Location) 'out\SHA256SUMS.txt'),$lines,[System.Text.Encoding]::ASCII)"
if errorlevel 1 (
    echo [ERROR] Failed to write SHA256SUMS.txt.
    exit /b 1
)

echo.
echo Build complete:
for %%T in (%TOOLS%) do echo   %CD%\out\%%T
echo   %CD%\out\SHA256SUMS.txt

echo.
echo Verification summary expected for every binary:
echo   Type: DYN
echo   INTERP: /system/bin/linker64
echo   NEEDED: libc.so required; libdl.so allowed
echo   LOAD alignment: 0x4000

echo.
echo Phone quick test:
echo   adb push out\filewatch out\propwait out\procwait out\unixsock out\netwatch out\uidexec /data/local/tmp/
echo   adb shell su -c "chmod 755 /data/local/tmp/filewatch /data/local/tmp/propwait /data/local/tmp/procwait /data/local/tmp/unixsock /data/local/tmp/netwatch /data/local/tmp/uidexec"
echo   adb shell su -c "/data/local/tmp/filewatch --version"
echo   adb shell su -c "/data/local/tmp/propwait --version"
echo   adb shell su -c "/data/local/tmp/procwait --version"
echo   adb shell su -c "/data/local/tmp/unixsock --version"
echo   adb shell su -c "/data/local/tmp/netwatch --version"
echo   adb shell su -c "/data/local/tmp/uidexec 0 0 /data -- /system/bin/id"
exit /b 0
