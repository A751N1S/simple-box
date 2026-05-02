# simple-box

Operations-Skripte fuer Windows-basierte Foto-/Druck-Boxen mit DNP DS620.
Selbst-Diagnose, Drucker-Verwaltung, Update-Politik, Health-Dashboard.

---

## Schnellstart

In PowerShell **als Administrator**:

```powershell
irm https://raw.githubusercontent.com/A751N1S/simple-box/main/bootstrap.ps1 | iex
```

Das Skript:
- Legt eine kanonische Folder-Struktur unter `C:\ateam\` an
- Kopiert die Box-Files an ihre richtigen Plaetze
- Registriert einen Health-Watchdog als Scheduled Task
- Legt einen Edge-Kiosk-Shortcut fuer das Dashboard an
- Prueft AnyDesk und Bonjour (mDNS)
- Setzt eine konservative Windows-Update-Politik (kein Auto-Reboot)
- Raeumt die Drucker auf (DS620-Geister + fremde Drucker)

---

## Repo-Layout

```
.
├── bootstrap.ps1                      <- Einstiegs-Skript fuer "irm | iex"
├── boxes/
│   └── ds620/                         <- Variante mit DNP DS620
│       ├── RUN-SETUP.cmd
│       ├── RUN-CLEANUP-PRINTERS.cmd
│       ├── install-from-downloads.ps1
│       ├── cleanup-printers-ds620.ps1
│       ├── box-watchdog.ps1
│       ├── box-dashboard.html
│       └── windows-update-policy.ps1
├── docs/
└── _internal/
```

---

## Was die einzelnen Skripte tun

**`install-from-downloads.ps1`** - Bootstrap der Folder-Struktur, kopiert Files,
registriert den Watchdog als Scheduled Task, legt den Edge-Kiosk-Shortcut an,
prueft AnyDesk und Bonjour, setzt die Update-Politik.

**`cleanup-printers-ds620.ps1`** - Raeumt die Windows-Drucker-Liste auf:
fremde Drucker werden entfernt, DS620-Geister werden entfernt, der online-DS620
wird zu `DP-DS620` umbenannt und als Default gesetzt.

**`box-watchdog.ps1`** - Self-Diagnose-Daemon, schreibt alle 10 Sekunden den
Status nach `C:\ateam\state\box-status.json` und `C:\ateam\dashboard\box-status.js`.
Acht parallele Checks: Internet, Bonjour, AnyDesk, Print Server, Drucker,
Drucker-Geister, Druckerrolle, iPad im LAN.

**`box-dashboard.html`** - Vollbild-Dashboard fuer einen Touchscreen oder
Hauptmonitor. Liest die `box-status.js` alle 5 Sekunden. Ampel-Stil
(gruen/gelb/rot).

**`windows-update-policy.ps1`** - Setzt Auto-Reboot auf "niemals", sperrt
Driver-Updates ueber Windows Update, verzoegert Feature-Updates 90 Tage.
Helper: `Suspend-WindowsUpdate -Days 35` und `Resume-WindowsUpdate`.

---

## Was hier NICHT reingehoert

- API-Keys, Webhook-URLs, Tokens
- Kunden-spezifische Configs
- Treiber-Installer (zu gross)

`webhook-config.json` und `secrets.*` sind in `.gitignore` ausgeschlossen.
Wenn du dir nicht sicher bist: lieber lokal lassen.

---

## Versionsgeschichte

Aenderungen siehe Git-Log:
```
git log --oneline
```
Oder im Browser: <https://github.com/A751N1S/simple-box/commits/main>
