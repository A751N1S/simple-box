@echo off
REM ============================================================
REM  BOX - DRUCKER-CLEANUP
REM  Doppelklicken. UAC-Prompt. Drucker werden bereinigt.
REM
REM  LOCAL hat Vorrang - wenn aus entpacktem ZIP-Ordner gestartet,
REM  nutzt das die NEUEN Files daneben, nicht die evtl. alten in
REM  C:\ateam\
REM ============================================================

setlocal
set "SCRIPT_DIR=%~dp0"
set "INSTALLED=C:\ateam\scripts\fotobox\cleanup-printers-ds620.ps1"
set "LOCAL=%SCRIPT_DIR%cleanup-printers-ds620.ps1"

if exist "%LOCAL%" (
    set "TARGET=%LOCAL%"
    echo Nutze LOKALE Version aus: %SCRIPT_DIR%
) else if exist "%INSTALLED%" (
    set "TARGET=%INSTALLED%"
    echo Nutze INSTALLIERTE Version: %INSTALLED%
) else (
    echo FEHLER: cleanup-printers-ds620.ps1 nicht gefunden.
    pause
    exit /b 1
)

NET SESSION >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TARGET%"

echo.
echo Cleanup beendet. Beliebige Taste zum Schliessen.
pause >nul
endlocal
