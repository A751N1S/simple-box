#Requires -RunAsAdministrator
<#
.SYNOPSIS
    User-Passwort auf einer Box zuruecksetzen.

.DESCRIPTION
    Wenn das Passwort eines lokalen User-Kontos vergessen wurde und du als
    Admin (anderer Account) eingeloggt bist, kannst du das Passwort hier neu
    setzen, ohne das alte zu kennen.

    Listet auch alle lokalen User auf, damit du den exakten Namen siehst.

.NOTES
    Stand: Samstag, 02.05.2026
    Voraussetzung: du bist mit einem Admin-Konto eingeloggt.

.EXAMPLE
    # User-Liste anzeigen
    powershell -ExecutionPolicy Bypass -File reset-user-password.ps1 -List

    # Passwort setzen (interaktiv, Eingabe verdeckt)
    powershell -ExecutionPolicy Bypass -File reset-user-password.ps1 -UserName "NEW ENGLAND PATRIOTS"

    # Passwort direkt setzen (nicht-interaktiv, Vorsicht: erscheint in History)
    powershell -ExecutionPolicy Bypass -File reset-user-password.ps1 -UserName "X" -NewPassword "Pwd123!"
#>

[CmdletBinding()]
param(
    [string]$UserName = "",
    [string]$NewPassword = "",
    [switch]$List
)

# Self-Heal: ExecutionPolicy
$currentPolicy = Get-ExecutionPolicy -Scope Process
if ($currentPolicy -ne "Bypass" -and $currentPolicy -ne "Unrestricted") {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath" @args
    exit $LASTEXITCODE
}

if ($List -or (-not $UserName)) {
    Write-Host ""
    Write-Host "=== Lokale Benutzer auf $env:COMPUTERNAME ===" -ForegroundColor Cyan
    Write-Host ""
    Get-LocalUser | ForEach-Object {
        $status = if ($_.Enabled) { "aktiv" } else { "deaktiviert" }
        $admin = ""
        try {
            $isAdmin = Get-LocalGroupMember -Group "Administrators" -Member $_.Name -ErrorAction SilentlyContinue
            if ($isAdmin) { $admin = " [ADMIN]" }
        } catch {}
        Write-Host ("  {0,-30} {1,-12}{2}" -f $_.Name, $status, $admin)
    }
    Write-Host ""
    if (-not $UserName) {
        Write-Host "Aufruf:  reset-user-password.ps1 -UserName ""<name>""" -ForegroundColor Yellow
        exit 0
    }
}

# Pruefen ob User existiert
$user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if (-not $user) {
    Write-Host "FEHLER: User '$UserName' existiert nicht." -ForegroundColor Red
    Write-Host "Tipp: -List zeigt alle User-Namen" -ForegroundColor Yellow
    exit 1
}

# Passwort holen
if ($NewPassword) {
    $secure = ConvertTo-SecureString -String $NewPassword -AsPlainText -Force
    Write-Host ""
    Write-Host "WARNUNG: Klartext-Passwort uebergeben. Erscheint in PowerShell-History!" -ForegroundColor Yellow
    Write-Host "Empfehlung: ohne -NewPassword aufrufen, dann interaktive Eingabe (verdeckt)." -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "Neues Passwort fuer '$UserName' setzen (Eingabe wird verdeckt):" -ForegroundColor Cyan
    $secure = Read-Host -AsSecureString
    if ($secure.Length -eq 0) {
        Write-Host "Abgebrochen - leeres Passwort nicht erlaubt." -ForegroundColor Red
        exit 1
    }
}

# Setzen
try {
    Set-LocalUser -Name $UserName -Password $secure -ErrorAction Stop
    Write-Host ""
    Write-Host "OK Passwort fuer '$UserName' wurde neu gesetzt." -ForegroundColor Green
    Write-Host ""
    Write-Host "Wichtig:" -ForegroundColor Yellow
    Write-Host "  - Falls Auto-Login gesetzt ist, muss das in netplwiz auch aktualisiert werden."
    Write-Host "  - In AnyDesk: keine Aktion noetig, der unbeaufsichtigte Zugriff laeuft ueber AnyDesk-Passwort,"
    Write-Host "    nicht ueber das Windows-Passwort."
    Write-Host ""
} catch {
    Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
