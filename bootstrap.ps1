<#
.SYNOPSIS
    Box Bootstrap - laedt Files aus dem GitHub-Repo + ruft Installer.

.DESCRIPTION
    Aufruf-Variante (Public Repo):

        irm https://raw.githubusercontent.com/A751N1S/simple-box/main/bootstrap.ps1 | iex

    Das Bootstrap:
    1. Hebt sich auf Admin-Rechte (UAC)
    2. Laedt alle Files aus boxes/<variante>/ in einen temp-Ordner
    3. Ruft den lokalen install-from-downloads.ps1 mit dem temp-Ordner als Quelle
    4. Ruft anschliessend den Drucker-Cleanup auf

.NOTES
    Stand: Samstag, 02.05.2026
    Box-Varianten: ds620
#>

[CmdletBinding()]
param(
    [string]$Variant   = "ds620",
    [string]$Branch    = "main",
    [string]$RepoOwner = "A751N1S",
    [string]$RepoName  = "simple-box"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Admin-Check
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Bootstrap braucht Admin-Rechte. Hebe an..." -ForegroundColor Yellow
    $cmdLine = "irm 'https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/bootstrap.ps1' | iex"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmdLine
    exit 0
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  BOX BOOTSTRAP" -ForegroundColor Cyan
Write-Host "  Repo:    $RepoOwner/$RepoName ($Branch)" -ForegroundColor Cyan
Write-Host "  Variant: $Variant" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$tempDir = Join-Path $env:TEMP "box-bootstrap-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Write-Host "Temp: $tempDir" -ForegroundColor DarkGray

$baseUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/boxes/$Variant"

$files = @(
    "RUN-SETUP.cmd",
    "RUN-CLEANUP-PRINTERS.cmd",
    "install-from-downloads.ps1",
    "cleanup-printers-ds620.ps1",
    "box-watchdog.ps1",
    "box-dashboard.html",
    "windows-update-policy.ps1"
)

Write-Host ""
Write-Host "Lade Files aus dem Repo..." -ForegroundColor Yellow
foreach ($f in $files) {
    $url  = "$baseUrl/$f"
    $dest = Join-Path $tempDir $f
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Write-Host "  OK  $f" -ForegroundColor Gray
    } catch {
        Write-Host "  FEHLER $f - $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  URL: $url" -ForegroundColor DarkGray
        exit 1
    }
}

Get-ChildItem $tempDir -File | Unblock-File

Write-Host ""
Write-Host "Files geladen. Starte Installer..." -ForegroundColor Green
Write-Host ""

$installer = Join-Path $tempDir "install-from-downloads.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -SourcePath $tempDir
$installerExit = $LASTEXITCODE

Write-Host ""
Write-Host "Starte Drucker-Cleanup..." -ForegroundColor Yellow
$cleanup = Join-Path $tempDir "cleanup-printers-ds620.ps1"
if (Test-Path $cleanup) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cleanup
}

Write-Host ""
Write-Host "Bootstrap fertig. Installer Exit-Code: $installerExit" -ForegroundColor Cyan
Write-Host "Temp-Ordner: $tempDir (kannst du loeschen oder behalten)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Naechste Schritte:" -ForegroundColor White
Write-Host "  1. Print Server schliessen + neu starten"
Write-Host "  2. Im iPad: Configure Printer erneut auswaehlen"
Write-Host "  3. Reboot zum finalen Test"
exit $installerExit
