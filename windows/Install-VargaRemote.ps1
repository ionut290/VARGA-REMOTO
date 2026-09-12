#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

if (-not (Test-VargaRemoteAdministrator)) {
    Write-Host 'Richiesta autorizzazione amministratore...' -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath)
    )
    exit
}

Clear-Host
Write-Host 'VARGA REMOTE - INSTALLAZIONE PC CONTROLLATO' -ForegroundColor Cyan
Write-Host 'Il controllo remoto sara visibile sul PC e revocabile localmente.'
Write-Host
$consent = Read-Host 'Se sei il proprietario o sei autorizzato, digita AUTORIZZO'
if ($consent -cne 'AUTORIZZO') {
    Write-Host 'Installazione annullata: consenso non confermato.' -ForegroundColor Yellow
    exit 1
}

$computerLabel = Read-Host 'Nome da assegnare a questo PC (es. PC Ufficio)'
if ([string]::IsNullOrWhiteSpace($computerLabel)) { $computerLabel = $env:COMPUTERNAME }

$rustDesk = Get-VargaRemoteRustDeskPath
if (-not $rustDesk) {
    Write-Host 'Download del client RustDesk ufficiale...' -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'VargaRemote-Installer' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/rustdesk/rustdesk/releases/latest' -Headers $headers
    $asset = $release.assets | Where-Object {
        $_.name -match 'x86_64\.exe$' -and $_.name -notmatch 'portable'
    } | Select-Object -First 1
    if (-not $asset) { throw 'Installer Windows x64 di RustDesk non trovato.' }

    $downloadPath = Join-Path $env:TEMP 'VargaRemote-RustDesk-Setup.exe'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -Headers $headers
    Write-Host 'Installazione del servizio RustDesk...' -ForegroundColor Cyan
    $process = Start-Process -FilePath $downloadPath -ArgumentList '--silent-install' -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installazione RustDesk non riuscita: codice $($process.ExitCode)." }
    Start-Sleep -Seconds 3
    $rustDesk = Get-VargaRemoteRustDeskPath
}

if (-not $rustDesk) { throw 'RustDesk installato ma eseguibile non rilevato.' }

Write-Host
Write-Host 'Crea la password permanente.' -ForegroundColor Cyan
Write-Host 'Usa almeno 12 caratteri, solo lettere e numeri, e conservala in un password manager.'
$plainPassword = $null
while ($true) {
    $secureOne = Read-Host 'Password' -AsSecureString
    $secureTwo = Read-Host 'Ripeti password' -AsSecureString
    $one = ConvertFrom-VargaRemoteSecureString $secureOne
    $two = ConvertFrom-VargaRemoteSecureString $secureTwo
    if ($one -ne $two) {
        Write-Host 'Le password non coincidono.' -ForegroundColor Red
        continue
    }
    if ($one.Length -lt 12 -or $one -notmatch '^[A-Za-z0-9]+$') {
        Write-Host 'Servono almeno 12 caratteri composti soltanto da lettere e numeri.' -ForegroundColor Red
        continue
    }
    $plainPassword = $one
    break
}

try {
    & $rustDesk --password $plainPassword | Out-Null
}
finally {
    $plainPassword = $null
    $one = $null
    $two = $null
}

$service = Get-Service -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like '*RustDesk*' -or $_.DisplayName -like '*RustDesk*'
} | Select-Object -First 1
if ($service) {
    Set-Service -Name $service.Name -StartupType Automatic
    if ($service.Status -ne 'Running') { Start-Service -Name $service.Name }
}

$id = $null
for ($attempt = 0; $attempt -lt 10 -and -not $id; $attempt++) {
    $candidate = (& $rustDesk --get-id 2>$null | Out-String).Trim()
    if ($candidate -match '(?m)^\s*([A-Za-z][A-Za-z0-9-]{5,}|[0-9]{6,})\s*$') {
        $id = $matches[1]
    }
    if (-not $id) { Start-Sleep -Seconds 1 }
}

$desktop = [Environment]::GetFolderPath('Desktop')
$infoPath = Join-Path $desktop 'Varga Remote - Dati PC.txt'
$lines = @(
    'VARGA REMOTE - DATI DEL PC',
    "Nome: $computerLabel",
    "Nome Windows: $env:COMPUTERNAME",
    "ID RustDesk: $id",
    "Installato: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    '',
    'La password NON e salvata in questo file.',
    'Per revocare: eseguire Revoca-accesso.cmd dal pacchetto Varga Remote.'
)
$lines | Set-Content -Path $infoPath -Encoding UTF8

Start-Process -FilePath $rustDesk
Write-Host
Write-Host 'INSTALLAZIONE COMPLETATA' -ForegroundColor Green
if ($id) { Write-Host "ID di questo PC: $id" -ForegroundColor Green }
Write-Host "Scheda salvata sul Desktop: $infoPath"
Write-Host
Write-Host 'Controllo finale in RustDesk > Impostazioni > Sicurezza:' -ForegroundColor Yellow
Write-Host '- Password o clic locale'
Write-Host '- Modalita privacy DISABILITATA'
Write-Host '- Blocco input locale DISABILITATO'
Write-Host '- Terminale remoto DISABILITATO'
Write-Host '- Trasferimento file soltanto se necessario'
