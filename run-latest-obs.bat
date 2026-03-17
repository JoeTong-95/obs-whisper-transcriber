@echo off
setlocal
cd /d "%~dp0"
title OBS Whisper Pipeline
echo ======================================
echo OBS to Whisper Transcription Pipeline
echo ======================================
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0process-latest-obs.ps1"
echo.
if errorlevel 1 (
    echo Pipeline failed. Review the messages above.
) else (
    echo Pipeline finished successfully.
)
echo.
pause
