@echo off
REM ============================================================
REM  BOX - RUN SETUP
REM  Doppelklicken. UAC-Prompt bestaetigen. Fertig.
REM ============================================================

setlocal
set "SCRIPT_DIR=%~dp0"
set "INSTALLER=%SCRIPT_DIR%install-from-downloads.ps1"
set "CLEANUP=%SCRIPT_DIR%cleanup-printers-ds620.ps1"

if not exist "%INSTALLER%" (
    echo.
    echo FEHLER: install-from-downloads.ps1 nicht gefunden.
    echo Erwartet im selben Ordner wie diese .cmd:
    echo   %INSTALLER%
    echo.
    pause
    exit /b 1
)

NET SESSION >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo Hebe auf Admin-Rechte... UAC-Prompt bestaetigen.
    echo.
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo.
echo === Box Installer wird gestartet ===
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%"

echo.
echo === Drucker-Cleanup wird gestartet ===
echo.
if exist "%CLEANUP%" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLEANUP%"
) else (
    echo WARNUNG: cleanup-printers-ds620.ps1 nicht gefunden.
)

echo.
echo === Setup komplett ===
echo.
echo Naechste Schritte:
echo  1. Print Server schliessen + neu starten
echo  2. Im iPad: "Configure Printer" erneut auswaehlen
echo  3. Reboot zum finalen Test
echo.
echo Beliebige Taste zum Schliessen.
pause >nul
endlocal
