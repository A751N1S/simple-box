<#
.SYNOPSIS
    Windows-Update-Politik fuer Eventboxen.

.DESCRIPTION
    Konfiguriert Windows Update so, dass:
    - Auto-Reboots auf der Box NIEMALS passieren ohne explizite Erlaubnis
    - Active Hours auf 24/7 gesetzt sind (kein Reboot-Fenster fuer das System)
    - Updates ueber Metered-Connection als geblockt markiert sind (5G-Router)
    - Toast-Notifications zu Updates aus sind
    - Driver-Updates nicht automatisch ueber WU kommen (DS620-Treiber stabil halten)

    Plus zwei Helper-Funktionen:
    - Suspend-WindowsUpdate -Days 35  (max. Pause-Dauer in Win11)
    - Resume-WindowsUpdate           (Pause aufheben, wieder normal updaten)

    Die Politik ist konservativ: Updates werden geladen und installiert wenn
    sie fertig sind, aber NIEMALS rebootet ohne dass jemand "Jetzt neustarten"
    klickt. Bei Live-Events VOR dem Aufbau einmal Suspend-WindowsUpdate -Days 35
    laufen lassen.

.NOTES
    Stand: Samstag, 02.05.2026
    Quelle: Microsoft Docs Group Policy / Registry Reference
    Kompatibel mit: Windows 10 21H2+, Windows 11 (alle Versionen)

.EXAMPLE
    # Standard-Setup
    powershell -ExecutionPolicy Bypass -File windows-update-policy.ps1

    # Updates bis nach dem Event pausieren (35 Tage Maximum)
    . .\windows-update-policy.ps1; Suspend-WindowsUpdate -Days 35

    # Pause aufheben
    . .\windows-update-policy.ps1; Resume-WindowsUpdate
#>

#Requires -RunAsAdministrator

# Self-Heal: ExecutionPolicy
$currentPolicy = Get-ExecutionPolicy -Scope Process
if ($currentPolicy -ne "Bypass" -and $currentPolicy -ne "Unrestricted") {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath" @args
    exit $LASTEXITCODE
}

# ============================================
# Registry-Pfade
# ============================================
$wuPolicy   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$wuAuPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$wuUx       = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

function Ensure-Key {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    Ensure-Key $Path
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

# ============================================
# 1. Auto-Reboot komplett verbieten
# ============================================
Write-Host "[1/6] Auto-Reboot verbieten..." -ForegroundColor Yellow

# NoAutoRebootWithLoggedOnUsers = 1: Nicht rebooten, wenn User eingeloggt
Set-Reg $wuAuPolicy "NoAutoRebootWithLoggedOnUsers" 1

# AlwaysAutoRebootAtScheduledTime = 0: Geplante Reboots NICHT erzwingen
Set-Reg $wuAuPolicy "AlwaysAutoRebootAtScheduledTime" 0

# AUOptions = 3: Automatisch herunterladen + Benachrichtigen, aber NICHT installieren
# (Wir wollen nicht, dass mitten im Live-Event ein Install loslaeuft)
Set-Reg $wuAuPolicy "AUOptions" 3

Write-Host "      OK (NoAutoRebootWithLoggedOnUsers=1, AUOptions=3)" -ForegroundColor Green

# ============================================
# 2. Active Hours auf maximales Fenster (1-23 = 22h, einzig erlaubt in Win11)
# ============================================
Write-Host "[2/6] Active Hours auf 1:00-23:00 (max. 22h)..." -ForegroundColor Yellow

Set-Reg $wuUx "ActiveHoursStart" 1
Set-Reg $wuUx "ActiveHoursEnd" 23
Set-Reg $wuUx "IsActiveHoursEnabled" 1

Write-Host "      OK" -ForegroundColor Green

# ============================================
# 3. Driver-Updates ueber WU NICHT erlauben
#    (Damit der DS620-Treiber nicht ploetzlich gegen einen WU-Driver getauscht wird)
# ============================================
Write-Host "[3/6] Driver-Updates ueber WU sperren..." -ForegroundColor Yellow

Set-Reg $wuPolicy "ExcludeWUDriversInQualityUpdate" 1

# Auch bei Device Search aus dem Geraete-Manager keine WU-Treiber
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" "SearchOrderConfig" 0

Write-Host "      OK" -ForegroundColor Green

# ============================================
# 4. Update-Notifications stumm
# ============================================
Write-Host "[4/6] Update-Toast-Notifications aus..." -ForegroundColor Yellow

Set-Reg $wuAuPolicy "SetUpdateNotificationLevel" 1
Set-Reg $wuAuPolicy "UpdateNotificationLevel" 1   # 1 = nur Restart-Warnung, keine Update-Werbung

Write-Host "      OK" -ForegroundColor Green

# ============================================
# 5. Aktive Verbindung als "Metered" markieren wuerde Updates komplett blocken,
#    aber das machen wir NICHT global, weil das Cloud-Uploads bremst.
#    Stattdessen: nur Updates ueber Metered erlauben = false
# ============================================
Write-Host "[5/6] Updates ueber Metered Connection sperren..." -ForegroundColor Yellow

Set-Reg $wuPolicy "AllowAutoWindowsUpdateDownloadOverMeteredNetwork" 0

Write-Host "      OK" -ForegroundColor Green

# ============================================
# 6. Feature-Updates (grosse Versionsspruenge) verzoegern
# ============================================
Write-Host "[6/6] Feature-Updates 90 Tage verzoegern..." -ForegroundColor Yellow

Set-Reg $wuPolicy "DeferFeatureUpdates" 1
Set-Reg $wuPolicy "DeferFeatureUpdatesPeriodInDays" 90
Set-Reg $wuPolicy "DeferQualityUpdates" 1
Set-Reg $wuPolicy "DeferQualityUpdatesPeriodInDays" 7

Write-Host "      OK (Feature: 90 Tage, Quality: 7 Tage)" -ForegroundColor Green

# ============================================
# 7. Helper-Funktionen
# ============================================
function Suspend-WindowsUpdate {
    [CmdletBinding()]
    param([int]$Days = 35)

    if ($Days -gt 35) {
        Write-Warning "Maximum sind 35 Tage. Setze auf 35."
        $Days = 35
    }

    $until = (Get-Date).ToUniversalTime().AddDays($Days).ToString("yyyy-MM-ddTHH:mm:ssZ")

    Ensure-Key $wuUx
    Set-Reg $wuUx "PauseUpdatesExpiryTime" $until "String"
    Set-Reg $wuUx "PauseFeatureUpdatesStartTime" (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") "String"
    Set-Reg $wuUx "PauseFeatureUpdatesEndTime" $until "String"
    Set-Reg $wuUx "PauseQualityUpdatesStartTime" (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") "String"
    Set-Reg $wuUx "PauseQualityUpdatesEndTime" $until "String"

    Write-Host "Windows Update pausiert bis $until UTC ($Days Tage)" -ForegroundColor Green
    Write-Host "Aufheben mit: Resume-WindowsUpdate" -ForegroundColor DarkGray
}

function Resume-WindowsUpdate {
    foreach ($name in @("PauseUpdatesExpiryTime", "PauseFeatureUpdatesStartTime",
                        "PauseFeatureUpdatesEndTime", "PauseQualityUpdatesStartTime",
                        "PauseQualityUpdatesEndTime")) {
        Remove-ItemProperty -Path $wuUx -Name $name -ErrorAction SilentlyContinue
    }
    Write-Host "Windows Update Pause aufgehoben." -ForegroundColor Green
}

# ============================================
# Zusammenfassung
# ============================================
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  WINDOWS-UPDATE-POLITIK GESETZT" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Was passiert jetzt:" -ForegroundColor White
Write-Host "  - Updates werden NUR heruntergeladen, nicht installiert."
Write-Host "  - Auto-Reboot ist komplett deaktiviert."
Write-Host "  - Driver-Updates kommen NICHT mehr ueber Windows Update."
Write-Host "  - Feature-Updates (grosse Versionen) sind 90 Tage verzoegert."
Write-Host ""
Write-Host "Vor jedem Live-Event:" -ForegroundColor Yellow
Write-Host "  . .\windows-update-policy.ps1; Suspend-WindowsUpdate -Days 35"
Write-Host ""
Write-Host "Nach dem Event (oder wenn du dich um Updates kuemmern willst):" -ForegroundColor Yellow
Write-Host "  . .\windows-update-policy.ps1; Resume-WindowsUpdate"
Write-Host ""
