@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo.
echo   ========================================
echo     O P E N H U M A N   P O R T A B L E
echo   ========================================
echo.

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: Detect architecture
if exist "%SCRIPT_DIR%\bin\windows-x64\OpenHuman.exe" (
    set "OPENHUMAN_BIN=%SCRIPT_DIR%\bin\windows-x64\OpenHuman.exe"
) else (
    echo   [ERROR] OpenHuman.exe not found in bin\windows-x64\
    echo   Run setup.sh first to download binaries.
    pause
    exit /b 1
)

:: Create data directories
if not exist "%SCRIPT_DIR%\data\.openhuman" mkdir "%SCRIPT_DIR%\data\.openhuman"
if not exist "%SCRIPT_DIR%\data\.openhuman\cef-cache" mkdir "%SCRIPT_DIR%\data\.openhuman\cef-cache"

:: First launch: show guide
if not exist "%SCRIPT_DIR%\data\.openhuman\.setup-done" (
    echo   First launch - opening setup guide...
    start "" "%SCRIPT_DIR%\lib\first-launch.html"
    echo. > "%SCRIPT_DIR%\data\.openhuman\.setup-done"
)

:: Set portable environment
set "OPENHUMAN_WORKSPACE=%SCRIPT_DIR%\data\.openhuman"
set "OPENHUMAN_CEF_CACHE_PATH=%SCRIPT_DIR%\data\.openhuman\cef-cache"

echo   Launching OpenHuman...
echo   Data: %SCRIPT_DIR%\data\.openhuman
echo.

start "" "%OPENHUMAN_BIN%"

echo   OpenHuman launched. You can close this window.
timeout /t 5 >nul
exit /b 0
