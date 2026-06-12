@echo off
chcp 65001 >nul
setlocal 

echo.
echo   ========================================
echo     O P E N H U M A N   P O R T A B L E
echo   ========================================
echo.

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: Detect binary
if exist "%SCRIPT_DIR%\bin\windows-x64\OpenHuman.exe" (
    set "OPENHUMAN_BIN=%SCRIPT_DIR%\bin\windows-x64\OpenHuman.exe"
) else if exist "%SCRIPT_DIR%\bin\windows-x64\OpenHuman-setup.exe" (
    echo   [!] Found installer: OpenHuman-setup.exe
    echo   Please run it once to extract OpenHuman.exe, then relaunch.
    start "" "%SCRIPT_DIR%\bin\windows-x64\OpenHuman-setup.exe"
    pause
    exit /b 0
) else (
    echo   [ERROR] OpenHuman not found in bin\windows-x64\
    echo   Run setup.sh first to download binaries.
    pause
    exit /b 1
)

:: Create portable home (zero host pollution)
if not exist "%SCRIPT_DIR%\data\.home" mkdir "%SCRIPT_DIR%\data\.home"
if not exist "%SCRIPT_DIR%\data\.openhuman" mkdir "%SCRIPT_DIR%\data\.openhuman"
if not exist "%SCRIPT_DIR%\data\.openhuman\cef-cache" mkdir "%SCRIPT_DIR%\data\.openhuman\cef-cache"

:: First launch: show guide
if not exist "%SCRIPT_DIR%\data\.openhuman\.setup-done" (
    echo   First launch - opening setup guide...
    start "" "%SCRIPT_DIR%\lib\first-launch.html"
    echo. > "%SCRIPT_DIR%\data\.openhuman\.setup-done"
)

:: Portable environment -- all paths stay inside the portable folder
set "HOME=%SCRIPT_DIR%\data\.home"
set "USERPROFILE=%SCRIPT_DIR%\data\.home"
set "OPENHUMAN_WORKSPACE=%SCRIPT_DIR%\data\.openhuman"
set "OPENHUMAN_CEF_CACHE_PATH=%SCRIPT_DIR%\data\.openhuman\cef-cache"

echo   Launching OpenHuman...
echo   Data: %SCRIPT_DIR%\data\.openhuman
echo.

:: Launch directly (not via start) to inherit HOME/USERPROFILE env vars
"%OPENHUMAN_BIN%"

exit /b 0
