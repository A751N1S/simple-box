#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Box One-Click-Installer (DS620-Variante).

.DESCRIPTION
    Erstellt die kanonische C:\ateam\-Struktur, kopiert die Box-Files
    aus dem Downloads-Ordner an ihre richtigen Plaetze, registriert den Watchdog
    als Scheduled Task (SYSTEM, AtStartup), legt einen Edge-Kiosk-Shortcut fuer das
    Dashboard im Startup-Folder an, prueft AnyDesk und Bonjour, setzt die
    Windows-Update-Politik.

    Idempotent: kann beliebig oft laufen.

.NOTES
    Stand: Samstag, 02.05.2026
    Workflow: Files via AnyDesk in Downloads ziehen -> diese .ps1 starten -> fertig.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install-from-downloads.ps1
#>

[CmdletBinding()]
param(
    [string]$SourcePath = "",
    [switch]$SkipTask,
    [switch]$SkipKiosk,
    [string]$EdgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
)

# Self-Heal: ExecutionPolicy
$currentPolicy = Get-ExecutionPolicy -Scope Process
if ($currentPolicy -ne "Bypass" -and $currentPolicy -ne "Unrestricted") {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    foreach ($k in $PSBoundParameters.Keys) {
        if ($PSBoundParameters[$k] -is [switch]) {
            if ($PSBoundParameters[$k]) { $argList += "-$k" }
        } else {
            $argList += "-$k"; $argList += "`"$($PSBoundParameters[$k])`""
        }
    }
    & powershell.exe @argList
    exit $LASTEXITCODE
}

# ExecutionPolicy permanent fuer die Maschine
try {
    $machinePolicy = Get-ExecutionPolicy -Scope LocalMachine
    if ($machinePolicy -in @("Restricted", "Undefined")) {
        Set-ExecutionPolicy -Scope LocalMachine RemoteSigned -Force -ErrorAction Stop
        Write-Host "[Pre] ExecutionPolicy LocalMachine: $machinePolicy -> RemoteSigned" -ForegroundColor Green
    }
} catch {
    Write-Host "[Pre] ExecutionPolicy konnte nicht gesetzt werden: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ============================================
# 1. Source-Path bestimmen
# ============================================
$candidatePaths = @()
if ($SourcePath) { $candidatePaths += $SourcePath }
$candidatePaths += "$env:USERPROFILE\Downloads\simple-box"
$candidatePaths += "$env:USERPROFILE\Downloads"

$source = $null
$required = @("cleanup-printers-ds620.ps1", "box-watchdog.ps1", "box-dashboard.html")
foreach ($p in $candidatePaths) {
    if (Test-Path $p) {
        $allThere = $true
        foreach ($r in $required) {
            if (-not (Test-Path (Join-Path $p $r))) { $allThere = $false; break }
        }
        if ($allThere) { $source = $p; break }
    }
}

if (-not $source) {
    Write-Host ""
    Write-Host "FEHLER: Konnte die Box-Files nicht finden." -ForegroundColor Red
    Write-Host "Erwartet werden alle DREI Files in einem dieser Ordner:" -ForegroundColor Yellow
    foreach ($p in $candidatePaths) { Write-Host "  - $p" }
    Write-Host ""
    Write-Host "Required: $($required -join ', ')"
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  BOX INSTALLER (DS620)" -ForegroundColor Cyan
Write-Host "  Quelle: $source" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# 2. Folder-Struktur
# ============================================
$folders = @(
    "C:\ateam",
    "C:\ateam\scripts",
    "C:\ateam\scripts\fotobox",
    "C:\ateam\config",
    "C:\ateam\config\fotobox",
    "C:\ateam\dashboard",
    "C:\ateam\state",
    "C:\ateam\logs",
    "C:\ateam\assets",
    "C:\ateam\assets\branding",
    "C:\ateam\tools"
)

Write-Host "[1/7] Folder-Struktur anlegen..." -ForegroundColor Yellow
foreach ($f in $folders) {
    if (-not (Test-Path $f)) {
        New-Item -ItemType Directory -Path $f -Force | Out-Null
        Write-Host "      angelegt: $f" -ForegroundColor Gray
    }
}
Write-Host "      OK" -ForegroundColor Green

# ============================================
# 3. Files kopieren
# ============================================
$copyMap = @(
    @{ src="cleanup-printers-ds620.ps1";  dst="C:\ateam\scripts\fotobox\cleanup-printers-ds620.ps1" }
    @{ src="box-watchdog.ps1";            dst="C:\ateam\scripts\fotobox\box-watchdog.ps1" }
    @{ src="box-dashboard.html";          dst="C:\ateam\dashboard\box-dashboard.html" }
    @{ src="windows-update-policy.ps1";   dst="C:\ateam\scripts\fotobox\windows-update-policy.ps1"; optional=$true }
    @{ src="install-from-downloads.ps1";  dst="C:\ateam\scripts\fotobox\install-from-downloads.ps1"; optional=$true }
)

Write-Host ""
Write-Host "[2/7] Files kopieren..." -ForegroundColor Yellow
foreach ($entry in $copyMap) {
    $srcFull = Join-Path $source $entry.src
    if (-not (Test-Path $srcFull)) {
        if ($entry.optional) { continue }
        Write-Host "      FEHLT: $($entry.src)" -ForegroundColor Red
        continue
    }
    Copy-Item -Path $srcFull -Destination $entry.dst -Force
    Write-Host "      $($entry.src) -> $($entry.dst)" -ForegroundColor Gray
}
Write-Host "      OK" -ForegroundColor Green

# ============================================
# 4. Scheduled Task fuer Watchdog
# ============================================
if (-not $SkipTask) {
    Write-Host ""
    Write-Host "[3/7] Scheduled Task fuer Watchdog registrieren..." -ForegroundColor Yellow

    $taskName = "ateam-box-watchdog"
    $watchdogPs = "C:\ateam\scripts\fotobox\box-watchdog.ps1"

    try {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host "      vorhandener Task entfernt" -ForegroundColor Gray
        }

        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchdogPs`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -StartWhenAvailable `
            -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)

        Register-ScheduledTask -TaskName $taskName -Action $action `
            -Trigger $trigger -Principal $principal -Settings $settings `
            -Description "Box Health Watchdog (alle 10s)" -Force | Out-Null

        Write-Host "      Task '$taskName' registriert" -ForegroundColor Gray

        Start-ScheduledTask -TaskName $taskName
        Start-Sleep -Seconds 2
        Write-Host "      OK (laeuft)" -ForegroundColor Green
    } catch {
        Write-Host "      FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "[3/7] Scheduled Task uebersprungen (-SkipTask)" -ForegroundColor DarkGray
}

# ============================================
# 5. Edge-Kiosk-Shortcut
# ============================================
if (-not $SkipKiosk) {
    Write-Host ""
    Write-Host "[4/7] Edge-Kiosk-Shortcut anlegen..." -ForegroundColor Yellow

    if (-not (Test-Path $EdgePath)) {
        Write-Host "      WARNUNG: Edge nicht unter $EdgePath gefunden" -ForegroundColor Yellow
    } else {
        $startup = [Environment]::GetFolderPath("Startup")

        $shortcutPath = Join-Path $startup "Box Dashboard.lnk"
        $dashboardUrl = "file:///C:/ateam/dashboard/box-dashboard.html"
        $userDataDir = "C:\ateam\dashboard\edge-profile"

        $args = "--kiosk `"$dashboardUrl`" --edge-kiosk-type=fullscreen " +
                "--no-first-run --disable-pinch --noerrdialogs " +
                "--user-data-dir=`"$userDataDir`""

        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $EdgePath
        $shortcut.Arguments = $args
        $shortcut.WorkingDirectory = "C:\ateam\dashboard"
        $shortcut.Description = "Box Health Dashboard (Kiosk)"
        $shortcut.Save()

        Write-Host "      Shortcut: $shortcutPath" -ForegroundColor Gray
        Write-Host "      OK (startet beim naechsten Login)" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "[4/7] Edge-Kiosk-Shortcut uebersprungen (-SkipKiosk)" -ForegroundColor DarkGray
}

# ============================================
# 6. AnyDesk-Service pruefen
# ============================================
Write-Host ""
Write-Host "[5/7] AnyDesk pruefen..." -ForegroundColor Yellow

$anydeskExe = "C:\Program Files (x86)\AnyDesk\AnyDesk.exe"
$anydeskExeAlt = "C:\Program Files\AnyDesk\AnyDesk.exe"

$anydeskInstalled = (Test-Path $anydeskExe) -or (Test-Path $anydeskExeAlt)
if (-not $anydeskInstalled) {
    Write-Host "      WARNUNG: AnyDesk nicht installiert (oder anderer Pfad)" -ForegroundColor Yellow
    Write-Host "      Download: https://anydesk.com/de/downloads/windows" -ForegroundColor DarkGray
} else {
    # Service-Modus: AnyDesk Service muss als Auto laufen
    $svc = Get-Service -Name "AnyDesk" -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.StartType -ne "Automatic") {
            Set-Service -Name "AnyDesk" -StartupType Automatic
            Write-Host "      AnyDesk-Service auf Automatic gesetzt" -ForegroundColor Gray
        }
        if ($svc.Status -ne "Running") {
            try {
                Start-Service -Name "AnyDesk"
                Write-Host "      AnyDesk-Service gestartet" -ForegroundColor Gray
            } catch {
                Write-Host "      AnyDesk-Service konnte nicht gestartet werden: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        Write-Host "      OK (Service-Modus, Automatic, laeuft)" -ForegroundColor Green
    } else {
        # AnyDesk installiert aber NICHT als Service - User-Mode
        # Prozess-Check und User-Autostart pruefen
        $proc = Get-Process -Name "AnyDesk" -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "      AnyDesk laeuft im User-Mode (PID $($proc[0].Id))" -ForegroundColor Gray
            Write-Host "      Empfehlung: AnyDesk-Settings -> Sicherheit -> 'AnyDesk-Dienst aktivieren'" -ForegroundColor DarkGray
            Write-Host "      OK (User-Mode, Fernzugriff nur bei eingeloggtem User)" -ForegroundColor Yellow
        } else {
            Write-Host "      WARNUNG: AnyDesk laeuft nicht. Bitte starten." -ForegroundColor Yellow
            Write-Host "      Empfehlung: in AnyDesk-Settings den Dienst aktivieren" -ForegroundColor DarkGray
        }
    }
}

# ============================================
# 7. Bonjour
# ============================================
Write-Host ""
Write-Host "[6/7] Bonjour-Service pruefen..." -ForegroundColor Yellow
$bonjour = Get-Service -Name "Bonjour Service" -ErrorAction SilentlyContinue
if ($bonjour) {
    if ($bonjour.StartType -ne "Automatic") {
        Set-Service -Name "Bonjour Service" -StartupType Automatic
        Write-Host "      Bonjour-StartType auf Automatic gesetzt" -ForegroundColor Gray
    }
    if ($bonjour.Status -ne "Running") {
        try { Start-Service -Name "Bonjour Service" } catch {}
    }
    Write-Host "      OK (laeuft, Automatic)" -ForegroundColor Green
} else {
    Write-Host "      WARNUNG: Bonjour nicht installiert" -ForegroundColor Yellow
    Write-Host "      mDNS-Discovery (z.B. fuer iPad-Print-Server-Erkennung) wird nicht funktionieren." -ForegroundColor DarkGray
    Write-Host "      Download: https://support.apple.com/kb/dl999" -ForegroundColor DarkGray
}

# ============================================
# 8. Windows-Update-Politik
# ============================================
$wuPolicyPs = "C:\ateam\scripts\fotobox\windows-update-policy.ps1"
if (Test-Path $wuPolicyPs) {
    Write-Host ""
    Write-Host "[7/7] Windows-Update-Politik setzen..." -ForegroundColor Yellow
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wuPolicyPs | Out-Null
        Write-Host "      OK (kein Auto-Reboot, Driver-Updates aus, Feature-Updates 90 Tage verzoegert)" -ForegroundColor Green
    } catch {
        Write-Host "      WARNUNG: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "[7/7] windows-update-policy.ps1 nicht gefunden -- Update-Politik unveraendert" -ForegroundColor DarkGray
}

# ============================================
# Zusammenfassung
# ============================================
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  INSTALLATION ABGESCHLOSSEN" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Naechste Schritte:" -ForegroundColor White
Write-Host "  1. Drucker-Cleanup als Admin laufen lassen:"
Write-Host "     RUN-CLEANUP-PRINTERS.cmd" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Watchdog testen:"
Write-Host "     powershell -File C:\ateam\scripts\fotobox\box-watchdog.ps1 -Once" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Dashboard im Browser oeffnen (Test):"
Write-Host "     start C:\ateam\dashboard\box-dashboard.html" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Reboot-Test: nach Neustart laeuft Watchdog + Dashboard automatisch" -ForegroundColor Gray
Write-Host ""
Write-Host "  Vor jedem Live-Event Updates pausieren:" -ForegroundColor Yellow
Write-Host "     . C:\ateam\scripts\fotobox\windows-update-policy.ps1; Suspend-WindowsUpdate -Days 35" -ForegroundColor Gray
Write-Host ""
exit 0
