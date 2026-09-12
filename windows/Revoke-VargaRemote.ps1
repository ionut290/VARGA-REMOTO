#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

if (-not (Test-VargaRemoteAdministrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath)
    )
    exit
}

Write-Host 'VARGA REMOTE - REVOCA ACCESSO PERMANENTE' -ForegroundColor Yellow
Write-Host 'La vecchia password smettera immediatamente di funzionare.'
$answer = Read-Host 'Digita REVOCA per continuare'
if ($answer -cne 'REVOCA') {
    Write-Host 'Revoca annullata.'
    exit 1
}

$rustDesk = Get-VargaRemoteRustDeskPath
if (-not $rustDesk) { throw 'RustDesk non trovato su questo PC.' }

$replacement = New-VargaRemotePassword -Length 64
try {
    & $rustDesk --password $replacement | Out-Null
}
finally {
    $replacement = $null
}

$services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like '*RustDesk*' -or $_.DisplayName -like '*RustDesk*'
})
foreach ($service in $services) {
    if ($service.Status -eq 'Running') { Stop-Service -Name $service.Name -Force }
}
Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($service in $services) { Start-Service -Name $service.Name }

Write-Host 'ACCESSO PERMANENTE REVOCATO' -ForegroundColor Green
Write-Host 'La password precedente non e piu valida.'
Write-Host 'Apri RustDesk > Impostazioni > Sicurezza e lascia attivo il clic locale'
Write-Host 'soltanto se vuoi consentire future sessioni approvate davanti al PC.'
Start-Process -FilePath $rustDesk

