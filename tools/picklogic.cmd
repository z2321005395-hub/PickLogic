@echo off
setlocal EnableExtensions

set "REPO_ROOT=%~dp0.."
if not defined PICKLOGIC_FLUTTER_ROOT set "PICKLOGIC_FLUTTER_ROOT=%USERPROFILE%\develop\picklogic-toolchain\flutter"
if not defined PICKLOGIC_ANDROID_TOOLCHAIN_ROOT set "PICKLOGIC_ANDROID_TOOLCHAIN_ROOT=%USERPROFILE%\Desktop\ttdt\toolchains"
set "ANDROID_HOME=%PICKLOGIC_ANDROID_TOOLCHAIN_ROOT%\android-sdk"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"

set "JAVA_HOME="
for /d %%D in ("%PICKLOGIC_ANDROID_TOOLCHAIN_ROOT%\jdk17\*") do if exist "%%~fD\bin\java.exe" set "JAVA_HOME=%%~fD"
set "GRADLE_HOME="
for /d %%D in ("%PICKLOGIC_ANDROID_TOOLCHAIN_ROOT%\gradle\*") do if exist "%%~fD\bin\gradle.bat" set "GRADLE_HOME=%%~fD"

if not exist "%PICKLOGIC_FLUTTER_ROOT%\bin\flutter.bat" (
  echo PICKLOGIC_TOOL_ERROR flutter_missing=true 1>&2
  exit /b 1
)
if not exist "%ANDROID_HOME%\platform-tools\adb.exe" (
  echo PICKLOGIC_TOOL_ERROR ttdt_android_sdk_missing=true 1>&2
  exit /b 1
)
if not exist "%JAVA_HOME%\bin\java.exe" (
  echo PICKLOGIC_TOOL_ERROR java17_missing=true 1>&2
  exit /b 1
)

set "PATH=%PICKLOGIC_FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%ANDROID_HOME%\cmdline-tools\latest\bin;%ANDROID_HOME%\emulator;%GRADLE_HOME%\bin;%PATH%"
set "DART=%PICKLOGIC_FLUTTER_ROOT%\bin\dart.bat"
set "FLUTTER=%PICKLOGIC_FLUTTER_ROOT%\bin\flutter.bat"

cd /d "%REPO_ROOT%"
if errorlevel 1 exit /b 1

if /i "%~1"=="env" goto env
if /i "%~1"=="pub-get" goto pub_get
if /i "%~1"=="privacy" goto privacy
if /i "%~1"=="licenses" goto licenses
if /i "%~1"=="quick" goto quick
if /i "%~1"=="full" goto full
if /i "%~1"=="android-debug" goto android_debug
if /i "%~1"=="android-release" goto android_release
if /i "%~1"=="windows-standard" goto windows_standard
if /i "%~1"=="windows-pro" goto windows_pro
goto usage

:env
echo PICKLOGIC_ENV_READY flutter=true android_sdk=true java17=true gradle=true ttdt_preferred=true
exit /b 0

:pub_get
call "%DART%" pub get
exit /b %ERRORLEVEL%

:privacy
call "%DART%" run tools\privacy_check.dart
exit /b %ERRORLEVEL%

:licenses
call "%DART%" run tools\dependency_license_check.dart
exit /b %ERRORLEVEL%

:quick
call "%DART%" format --output=none --set-exit-if-changed .
if errorlevel 1 exit /b 1
call "%DART%" analyze
if errorlevel 1 exit /b 1
call "%DART%" run tools\run_module_tests.dart quick
if errorlevel 1 exit /b 1
call "%DART%" run tools\dependency_license_check.dart
if errorlevel 1 exit /b 1
call "%DART%" run tools\privacy_check.dart
if errorlevel 1 exit /b 1
echo PICKLOGIC_CHECKS_OK scope=Quick
exit /b 0

:full
call "%~f0" quick
if errorlevel 1 exit /b 1
call "%DART%" run tools\run_module_tests.dart remaining
if errorlevel 1 exit /b 1
echo PICKLOGIC_CHECKS_OK scope=Full
exit /b 0

:android_debug
pushd apps\mobile
call "%FLUTTER%" build apk --debug
set "RESULT=%ERRORLEVEL%"
popd
exit /b %RESULT%

:android_release
pushd apps\mobile
call "%FLUTTER%" build apk --release
set "RESULT=%ERRORLEVEL%"
popd
exit /b %RESULT%

:windows_standard
pushd apps\desktop
call "%FLUTTER%" build windows --release --target lib\main_standard.dart
set "RESULT=%ERRORLEVEL%"
popd
exit /b %RESULT%

:windows_pro
pushd apps\desktop
call "%FLUTTER%" build windows --release --target lib\main_pro.dart
set "RESULT=%ERRORLEVEL%"
popd
exit /b %RESULT%

:usage
echo Usage: tools\picklogic.cmd ^<env^|pub-get^|privacy^|licenses^|quick^|full^|android-debug^|android-release^|windows-standard^|windows-pro^>
exit /b 2
