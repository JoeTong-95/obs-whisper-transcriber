@echo off
setlocal
cd /d "%~dp0"
title OBS Whisper Setup
echo ======================================
echo OBS Whisper Setup
echo ======================================
echo.
where python >nul 2>nul
if errorlevel 1 (
    echo Python was not found in PATH.
    echo Install Python 3.10+ and try again.
    echo.
    pause
    exit /b 1
)
where ffmpeg >nul 2>nul
if errorlevel 1 (
    echo ffmpeg was not found in PATH.
    echo Install ffmpeg and make sure it is available in your terminal.
    echo.
    pause
    exit /b 1
)
python -m pip install --upgrade pip
if errorlevel 1 goto :fail
python -m pip install -r requirements.txt
if errorlevel 1 goto :fail
echo.
echo Setup complete.
echo Models are downloaded automatically on first use unless already cached.
echo.
pause
exit /b 0
:fail
echo.
echo Setup failed.
echo.
pause
exit /b 1
