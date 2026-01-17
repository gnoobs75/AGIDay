@echo off
REM AGI Day - Editor Launcher with Logging
REM Logs are written to logs/editor_YYYYMMDD_HHMMSS.log

setlocal enabledelayedexpansion

REM Create timestamp for log filename
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set TIMESTAMP=%datetime:~0,8%_%datetime:~8,6%

set LOGFILE=logs\editor_%TIMESTAMP%.log
set LATEST=logs\editor_latest.log

echo Starting AGI Day Editor...
echo Log file: %LOGFILE%
echo.

REM Run editor with console output piped to log file
"C:\Godot\Godot_v4.5.1-stable_mono_win64_console.exe" --path "%~dp0" --editor 2>&1 | tee %LOGFILE%

REM Copy to latest after editor closes
copy /Y %LOGFILE% %LATEST% >nul 2>&1

echo.
echo Editor closed. Log saved to %LOGFILE%
pause
