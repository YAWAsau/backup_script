@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "API=23"
set "NDK_VERSION=25.2.9519653"

echo ============================================================
echo Android arm64 netwatch compatibility builder
echo API : %API%
echo NDK : r25c (%NDK_VERSION%)
echo Type: fully static ELF executable
echo ============================================================

set "SDK_ROOT="
if defined ANDROID_SDK_ROOT set "SDK_ROOT=%ANDROID_SDK_ROOT%"
if not defined SDK_ROOT if defined ANDROID_HOME set "SDK_ROOT=%ANDROID_HOME%"
if not defined SDK_ROOT set "SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"

set "NDK_ROOT=%SDK_ROOT%\ndk\%NDK_VERSION%"
if defined NETWATCH_NDK_ROOT set "NDK_ROOT=%NETWATCH_NDK_ROOT%"

if not exist "%NDK_ROOT%\source.properties" (
    echo [ERROR] Required Android NDK r25c was not found:
    echo   %NDK_ROOT%
    echo.
    echo Install it side by side with:
    echo   sdkmanager "ndk;%NDK_VERSION%"
    echo.
    echo Or set an exact extracted r25c path:
    echo   set NETWATCH_NDK_ROOT=D:\Android\android-ndk-r25c
    echo   build_windows.bat
    exit /b 1
)

findstr /C:"Pkg.Revision = %NDK_VERSION%" "%NDK_ROOT%\source.properties" >nul
if errorlevel 1 (
    echo [ERROR] NDK path exists, but it is not r25c %NDK_VERSION%:
    echo   %NDK_ROOT%
    type "%NDK_ROOT%\source.properties"
    exit /b 1
)

set "TOOLCHAIN=%NDK_ROOT%\toolchains\llvm\prebuilt\windows-x86_64\bin"
set "CC=%TOOLCHAIN%\aarch64-linux-android%API%-clang.cmd"
set "STRIP=%TOOLCHAIN%\llvm-strip.exe"
set "READELF=%TOOLCHAIN%\llvm-readelf.exe"

if not exist "%CC%" (
    echo [ERROR] Compiler wrapper not found:
    echo   %CC%
    exit /b 1
)

if not exist "out" mkdir "out"
del /q "out\netwatch" "out\netwatch.o" "out\netwatch.sha256.txt" 2>nul

set "CFLAGS=-std=c11 -Os -fvisibility=hidden -ffunction-sections -fdata-sections -Wall -Wextra -Werror"
set "LDFLAGS=-static -Wl,--gc-sections -Wl,-z,relro,-z,now -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"

echo [1/6] Compiling for Android API %API%...
call "%CC%" %CFLAGS% -c "netwatch.c" -o "out\netwatch.o"
if errorlevel 1 (
    echo [ERROR] Source compilation failed.
    exit /b 1
)
if not exist "out\netwatch.o" (
    echo [ERROR] Compiler returned without creating out\netwatch.o.
    exit /b 1
)
echo [OK] Object file created.

echo [2/6] Linking fully static executable...
call "%CC%" "out\netwatch.o" %LDFLAGS% -o "out\netwatch"
if errorlevel 1 (
    echo [ERROR] Link failed.
    exit /b 1
)
if not exist "out\netwatch" (
    echo [ERROR] Linker returned without creating out\netwatch.
    exit /b 1
)
echo [OK] Executable created.

echo [3/6] Stripping symbols...
"%STRIP%" --strip-all "out\netwatch"
if errorlevel 1 exit /b 1

echo [4/6] Verifying static ELF and 16 KB alignment...
"%READELF%" -h "out\netwatch" | findstr /C:"Class:" /C:"Type:" /C:"Machine:"
echo.
"%READELF%" -h "out\netwatch" | findstr /C:"Type:" | findstr /C:"EXEC" >nul
if errorlevel 1 (
    echo [ERROR] ELF type is not EXEC.
    exit /b 1
)

"%READELF%" -l "out\netwatch" | findstr /C:"INTERP" >nul
if not errorlevel 1 (
    echo [ERROR] INTERP segment found. Output is dynamically linked.
    exit /b 1
)

"%READELF%" -d "out\netwatch" 2>nul | findstr /C:"NEEDED" >nul
if not errorlevel 1 (
    echo [ERROR] NEEDED dependency found. Output is not fully static.
    exit /b 1
)

echo No INTERP and no NEEDED entries: fully static confirmed.
echo.
echo LOAD segment alignment:
"%READELF%" -lW "out\netwatch" | findstr /R /C:"[ ]LOAD[ ]"
"%READELF%" -lW "out\netwatch" | findstr /R /C:"[ ]LOAD[ ].*0x4000" >nul
if errorlevel 1 (
    echo [ERROR] One or more LOAD segments are not aligned to 16 KB ^(0x4000^).
    exit /b 1
)
echo 16 KB page-size alignment confirmed.

echo [5/6] Showing Android build note...
"%READELF%" -n "out\netwatch"

echo [6/6] Writing SHA-256...
set "NETWATCH_HASH="
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath 'out\netwatch').Hash.ToLowerInvariant()"`) do set "NETWATCH_HASH=%%H"
if not defined NETWATCH_HASH (
    echo [ERROR] Failed to calculate SHA-256.
    exit /b 1
)
> "out\netwatch.sha256.txt" echo %NETWATCH_HASH%  netwatch
if errorlevel 1 (
    echo [ERROR] Failed to write SHA-256 file.
    exit /b 1
)

del /q "out\netwatch.o" 2>nul

echo.
echo Build complete:
echo   %CD%\out\netwatch
echo   %CD%\out\netwatch.sha256.txt
echo.
echo Expected phone-side file result:
echo   ELF executable, 64-bit LSB arm64, static, for Android 23,
echo   built by NDK r25c (9519653), stripped
echo   no INTERP / no NEEDED / LOAD alignment 0x4000
echo.
echo Phone verification:
echo   adb push out\netwatch /data/local/tmp/netwatch
echo   adb shell su -c "chmod 755 /data/local/tmp/netwatch"
echo   adb shell su -c "file /data/local/tmp/netwatch"
echo   adb shell su -c "/data/local/tmp/netwatch --version"
echo   adb shell su -c "/data/local/tmp/netwatch"
echo.
echo Keep the final command running and toggle Wi-Fi.
exit /b 0
