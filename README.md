# simple-box

PowerShell-Skripte um eine Windows-Box mit DNP DS620 Drucker einzurichten und
am Leben zu halten. Bootstrap, Drucker-Cleanup, Health-Watchdog mit kleinem
Status-Dashboard.

## Setup

PowerShell als Admin auf der Box:

    irm https://raw.githubusercontent.com/A751N1S/simple-box/main/bootstrap.ps1 | iex

Holt die Files, legt sie nach `C:\ateam\`, registriert den Watchdog als
Scheduled Task, baut einen Edge-Kiosk-Shortcut fuer das Dashboard, prueft
AnyDesk und Bonjour, raeumt die Drucker auf.

Logs unter `C:\ateam\logs\`.

## Layout

    bootstrap.ps1
    boxes/
      ds620/        Variante mit DNP DS620
    docs/
