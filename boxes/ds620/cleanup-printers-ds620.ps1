#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Drucker-Cleanup fuer Box mit DS620.

.DESCRIPTION
    Raeumt die Drucker-Liste auf:
    - Fremde Drucker (HP, OneNote, etc.) werden IMMER entfernt
    - DS620-Geister je nach Online-Status:
      * 0 online: alle DS620 entfernen (alle sind Geister)
      * 1 online: Geister entfernen, online-Drucker zu DP-DS620 umbenennen + Default
      * >1 online: Warnung, manuelle Pruefung noetig

    Microsoft Print to PDF / XPS bleiben immer erhalten.
    Sicher gegen Mehrfach-Ausfuehrung. Idempotent.

.NOTES
    Stand: Samstag, 02.05.2026
    Ziel : ein einziger Drucker namens "DP-DS620" als Default

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File cleanup-printers-ds620.ps1
#>

[CmdletBinding()]
param(
    [string]$LogPath = "C:\ateam\logs\printer-cleanup.log",
    [string]$TargetName = "DP-DS620"
)

# Self-Heal: ExecutionPolicy
$currentPolicy = Get-ExecutionPolicy -Scope Process
if ($currentPolicy -ne "Bypass" -and $currentPolicy -ne "Unrestricted") {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath" `
        -LogPath $LogPath -TargetName $TargetName
    exit $LASTEXITCODE
}

# --- Logging-Setup ---
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    $line | Tee-Object -FilePath $LogPath -Append
}

Write-Log "INFO" "=== Drucker-Cleanup gestartet ==="

# --- Schritt 1: Komplettes Drucker-Inventar ---
$allPrinters = Get-CimInstance Win32_Printer
$keepNames = @(
    "Microsoft Print to PDF",
    "Microsoft XPS Document Writer",
    "Fax",
    $TargetName
)

# Fremde = nicht DS620 und nicht in der Whitelist
$foreign = $allPrinters | Where-Object {
    $_.DriverName -notmatch "DS620" -and
    $_.Name -notin $keepNames
}

# DS620 (alle, online + offline)
$allDS620 = $allPrinters | Where-Object {
    $_.DriverName -match "DS620" -or $_.Name -match "DS620"
}

$onlineDS620 = $allDS620 | Where-Object { -not $_.WorkOffline }
$offlineDS620 = $allDS620 | Where-Object { $_.WorkOffline }

Write-Log "INFO" ("Inventar: {0} fremde Drucker, {1} DS620 ({2} online, {3} offline)" -f `
    $foreign.Count, $allDS620.Count, $onlineDS620.Count, $offlineDS620.Count)

# --- Schritt 2: Fremde Drucker IMMER entfernen ---
foreach ($f in $foreign) {
    Write-Log "INFO" "Entferne Fremd-Drucker: $($f.Name) (Driver: $($f.DriverName))"
    try {
        Remove-Printer -Name $f.Name -ErrorAction Stop
        Write-Log "OK" "  -> entfernt: $($f.Name)"
    } catch {
        try {
            Invoke-CimMethod -InputObject $f -MethodName "Delete" -ErrorAction Stop | Out-Null
            Write-Log "OK" "  -> entfernt (CIM-Fallback): $($f.Name)"
        } catch {
            Write-Log "WARN" "  -> konnte $($f.Name) nicht entfernen: $($_.Exception.Message)"
        }
    }
}

# --- Schritt 3: DS620-Behandlung je nach Online-Count ---
if ($onlineDS620.Count -eq 0) {
    # Niemand online: DS620-Geister UNBERUEHRT lassen
    # Begruendung: wenn das exakt gleiche Geraet zurueckkommt, behaelt Windows die
    # Bindung an Treibereinstellungen, Druckwarteschlangen-Verhalten etc.
    # Pauschal entfernen wuerde diese Bindung zerstoeren.
    if ($allDS620.Count -gt 0) {
        Write-Log "WARN" "Kein DS620 online ($($allDS620.Count) offline). DS620-Drucker bleiben unberuehrt."
        Write-Log "INFO" "Drucker physisch anschliessen + einschalten, dann dieses Skript erneut laufen lassen."
        Write-Log "INFO" "Die Geister werden dann automatisch entfernt + der echte Drucker zu DP-DS620 normalisiert."
    } else {
        Write-Log "INFO" "Keine DS620-Drucker im System."
    }
}
elseif ($onlineDS620.Count -gt 1) {
    Write-Log "WARN" "Mehrere Online-DS620 ($($onlineDS620.Count)) - manuelle Pruefung noetig. Keine Aktion."
    $onlineDS620 | ForEach-Object { Write-Log "WARN" ("  -> {0} (Port: {1})" -f $_.Name, $_.PortName) }
}
else {
    # Genau 1 online: Standardfall
    Write-Log "INFO" "Genau 1 DS620 online -> Standardfall: rename + default"

    # Geister entfernen
    foreach ($g in $offlineDS620) {
        Write-Log "INFO" "Entferne DS620-Geist: $($g.Name)"
        try {
            Remove-Printer -Name $g.Name -ErrorAction Stop
            Write-Log "OK" "  -> Geist entfernt: $($g.Name)"
        } catch {
            try {
                Invoke-CimMethod -InputObject $g -MethodName "Delete" -ErrorAction Stop | Out-Null
                Write-Log "OK" "  -> Geist entfernt (CIM-Fallback): $($g.Name)"
            } catch {
                Write-Log "ERR" "  -> konnte $($g.Name) nicht entfernen: $($_.Exception.Message)"
            }
        }
    }

    # Online-Drucker normalisieren
    $real = $onlineDS620[0]
    if ($real.Name -ne $TargetName) {
        Write-Log "INFO" "Benenne $($real.Name) um nach $TargetName"
        try {
            Rename-Printer -Name $real.Name -NewName $TargetName -ErrorAction Stop
            Write-Log "OK" "  -> umbenannt zu $TargetName"
        } catch {
            Write-Log "ERR" "  -> Rename scheiterte: $($_.Exception.Message)"
        }
    } else {
        Write-Log "OK" "Drucker heisst bereits korrekt: $TargetName"
    }

    # Default setzen
    $defaultPrinter = Get-CimInstance Win32_Printer | Where-Object { $_.Name -eq $TargetName }
    if ($defaultPrinter) {
        try {
            Invoke-CimMethod -InputObject $defaultPrinter -MethodName "SetDefaultPrinter" -ErrorAction Stop | Out-Null
            Write-Log "OK" "$TargetName als Default gesetzt"
        } catch {
            Write-Log "WARN" "Default-Setzung scheiterte: $($_.Exception.Message)"
        }
    }
}

# --- Schritt 4: Spooler immer restarten ---
try {
    Restart-Service -Name Spooler -Force -ErrorAction Stop
    Write-Log "OK" "Print Spooler neu gestartet"
} catch {
    Write-Log "WARN" "Spooler-Restart scheiterte: $($_.Exception.Message)"
}

# --- Schritt 5: Endzustand loggen ---
Write-Log "INFO" "=== Cleanup abgeschlossen ==="
Write-Log "INFO" "Endzustand der Drucker:"
$endState = Get-CimInstance Win32_Printer
if ($endState) {
    foreach ($p in $endState) {
        Write-Log "INFO" ("  - {0,-30} Driver: {1,-25} Default: {2}" -f $p.Name, $p.DriverName, $p.Default)
    }
} else {
    Write-Log "INFO" "  (keine Drucker mehr installiert)"
}

Write-Log "INFO" ""
Write-Log "INFO" "Hinweis: Print Server muss neu gestartet werden, damit er den DS620 unter dem neuen Namen bindet."
exit 0
