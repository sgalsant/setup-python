@echo off
setlocal

REM Run the PowerShell setup script located in the same folder as this BAT file.
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%setup_python_environment.ps1"

if not exist "%PS_SCRIPT%" (
    echo.
    echo ERROR: PowerShell script not found:
    echo "%PS_SCRIPT%"
    echo.
    echo Make sure this BAT file and setup_python_environment_corrected.ps1
    echo are in the same folder.
    echo.
    pause
    exit /b 1
)

echo.
echo Starting Python workstation setup...
echo Use -PyData to also create a data analysis project.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*

set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo Setup completed successfully.
) else (
    echo Setup finished with errors. Exit code: %EXIT_CODE%
)

echo.
pause
exit /b %EXIT_CODE%
