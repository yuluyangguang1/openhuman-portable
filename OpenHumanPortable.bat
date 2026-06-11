@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title OpenHuman Portable

REM Clear conflicting env vars from inherited environment
set "OPENHUMAN_WORKSPACE="
set "OPENHUMAN_CEF_CACHE_PATH="

REM Enable ANSI escape codes
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

echo(
echo %ESC%[38;5;45m  ============================================%ESC%[0m
echo %ESC%[38;5;33m     O P E N H U M A N   P O R T A B L E%ESC%[0m
echo %ESC%[38;5;45m  ============================================%ESC%[0m
echo(

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"
set "BIN_DIR=%SCRIPT_DIR%bin\windows-x64"
set "PORTABLE_DATA=%SCRIPT_DIR%data"
set "PORTABLE_OPENHUMAN=%PORTABLE_DATA%\.openhuman"
set "LIB_DIR=%SCRIPT_DIR%lib"
set "RUN_LOCK=%PORTABLE_DATA%\.running"

REM Remove trailing backslash from SCRIPT_DIR for PS scripts
REM SCRIPT_DIR_PS removed (unused)

REM ===========================================
REM Check binary exists
REM ===========================================
if not exist "!BIN_DIR!\OpenHuman.exe" (
  echo [ERROR] OpenHuman not found: !BIN_DIR!\OpenHuman.exe
  pause
  exit /b 1
)

REM ===========================================
REM Single-instance check (atomic via mkdir)
REM ===========================================
if not exist "!PORTABLE_DATA!" mkdir "!PORTABLE_DATA!" >nul 2>&1
if exist "%RUN_LOCK%" (
  set "PREV_PID="
  if exist "%RUN_LOCK%\pid" (
    for /f "usebackq delims=" %%P in ("%RUN_LOCK%\pid") do if not defined PREV_PID set "PREV_PID=%%P"
  )
  if defined PREV_PID (
    tasklist /fi "PID eq !PREV_PID!" 2>nul | find "!PREV_PID!" >nul
    if !errorlevel! EQU 0 (
      echo   [info] Another instance is already running ^(PID !PREV_PID!^).
      timeout /t 5 >nul 2>&1
      exit /b 1
    )
  )
  rd /s /q "%RUN_LOCK%" >nul 2>&1
)
mkdir "%RUN_LOCK%" 2>nul
if !errorlevel! NEQ 0 (
  echo   [info] Another instance is already running ^(concurrent start^).
  timeout /t 5 >nul 2>&1
  exit /b 1
)

:: Write run-lock PID
for /f "delims=" %%P in ('powershell -NoProfile -Command "$p1=$PID;$p2=(Get-CimInstance Win32_Process -Filter ProcessId=$p1).ParentProcessId;$p3=(Get-CimInstance Win32_Process -Filter ProcessId=$p2).ParentProcessId;Write-Output $p3" 2^>nul') do set "MY_PID=%%P"
if not defined MY_PID set "MY_PID=%RANDOM%%RANDOM%%RANDOM%"
(echo !MY_PID!)>"%RUN_LOCK%\pid"

REM ===========================================
REM Setup portable directories
REM ===========================================
if not exist "%PORTABLE_OPENHUMAN%" mkdir "%PORTABLE_OPENHUMAN%"
if not exist "%PORTABLE_OPENHUMAN%\cef-cache" mkdir "%PORTABLE_OPENHUMAN%\cef-cache"

REM ===========================================
REM Kill orphaned config server from previous Ctrl+C (port 17600)
REM ===========================================
for /f "tokens=5" %%P in ('netstat -ano 2^>nul ^| findstr ":17600 " ^| findstr "LISTEN"') do (
  taskkill /pid %%P /f >nul 2>&1
)

REM ===========================================
REM Find Python: system > bundled
REM ===========================================
set "PYTHON_CMD="
where python3 >nul 2>&1
if !errorlevel! equ 0 (
  python3 --version >nul 2>&1
  if !errorlevel! equ 0 set "PYTHON_CMD=python3"
)
if not defined PYTHON_CMD (
  where python >nul 2>&1
  if !errorlevel! equ 0 (
    python --version >nul 2>&1
    if !errorlevel! equ 0 set "PYTHON_CMD=python"
  )
)
if not defined PYTHON_CMD (
  if exist "!BIN_DIR!\python\python.exe" set "PYTHON_CMD=!BIN_DIR!\python\python.exe"
)

REM ===========================================
REM Start config center (foreground, blocking)
REM ===========================================
set "CONFIG_SERVER=%LIB_DIR%\config_server.py"

if defined PYTHON_CMD (
  REM Test if Python actually works
  echo   Testing Python...
  "!PYTHON_CMD!" -c "import sys; print('Python', sys.version)" 2>&1
  if !errorlevel! neq 0 (
    echo   [!] Python test FAILED. Cannot start config center.
    echo   Python: !PYTHON_CMD!
    echo   Press any key to continue without config center...
    pause >nul
    goto :launch_openhuman
  )
  echo   Starting config center http://127.0.0.1:17600 ...
  echo   Configure provider and key, then click "Start OpenHuman".
  echo(
  REM Run config center in foreground (blocking) - waits for user to click "Start"
  "!PYTHON_CMD!" "!CONFIG_SERVER!"
  echo   Config center closed. Starting OpenHuman...
  echo(
) else (
  echo   [!] No Python found. Config center cannot start.
  echo   Continuing with existing config...
  timeout /t 3 >nul 2>&1
)

:launch_openhuman
REM ===========================================
REM Launch OpenHuman GUI
REM ===========================================
echo   Mode: Direct ^| Data: portable folder
echo(

set "OPENHUMAN_WORKSPACE=%PORTABLE_OPENHUMAN%"
set "OPENHUMAN_CEF_CACHE_PATH=%PORTABLE_OPENHUMAN%\cef-cache"

"%BIN_DIR%\OpenHuman.exe" %*
goto :final_cleanup

:error_cleanup
call :do_cleanup
pause
exit /b 1

:final_cleanup
call :do_cleanup
exit /b 0

:do_cleanup
if exist "%RUN_LOCK%" rd /s /q "%RUN_LOCK%" >nul 2>&1
exit /b 0
