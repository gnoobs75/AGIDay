@echo off
REM AGI Day - Game Launcher with Logging
REM Logs are written to logs/game_YYYYMMDD_HHMMSS.log

setlocal enabledelayedexpansion

REM Create timestamp for log filename
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set TIMESTAMP=%datetime:~0,8%_%datetime:~8,6%

set LOGFILE=logs\game_%TIMESTAMP%.log
set LATEST=logs\game_latest.log

echo Starting AGI Day...
echo Log file: %LOGFILE%
echo.

REM Run game with console output piped to log file
REM Also copy to latest.log for easy access
"C:\Godot\Godot_v4.5.1-stable_mono_win64_console.exe" --path "%~dp0" 2>&1 | tee %LOGFILE%

REM Copy to latest after game closes
copy /Y %LOGFILE% %LATEST% >nul 2>&1

echo.
echo Game closed. Log saved to %LOGFILE%
pause
