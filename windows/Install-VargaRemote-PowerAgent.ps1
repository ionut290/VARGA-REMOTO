#requires -Version 5.1
[CmdletBinding()]
param([switch]$Automatic, [switch]$RefreshOnly)

$ErrorActionPreference = 'Stop'
$commonPath = Join-Path $PSScriptRoot 'Common.ps1'
if (Test-Path $commonPath) { . $commonPath }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Esegui questo file come amministratore sul PC da controllare.'
}

$tailscale = @(Get-Command tailscale.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
$tailscale += @(
    "$env:ProgramFiles\Tailscale\tailscale.exe",
    "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
) | Where-Object { $_ -and (Test-Path $_) }
$tailscale = $tailscale | Where-Object { $_ } | Select-Object -First 1
if (-not $tailscale) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { throw 'Installazione automatica Tailscale non disponibile: winget non trovato.' }
    Write-Host 'Installazione automatica di Tailscale...' -ForegroundColor Cyan
    & $winget.Source install --id Tailscale.Tailscale --exact --silent --accept-source-agreements --accept-package-agreements
    $tailscale = @(
        "$env:ProgramFiles\Tailscale\tailscale.exe",
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $tailscale) { throw 'Tailscale non e stato installato correttamente.' }
}
$tailIp = (& $tailscale ip -4 2>$null | Select-Object -First 1).Trim()
if ($tailIp -notmatch '^100\.') {
    Write-Host 'Completa l accesso a Tailscale nella pagina che si apre...' -ForegroundColor Yellow
    Start-Process -FilePath $tailscale -ArgumentList @('up')
    $deadline = (Get-Date).AddMinutes(4)
    do {
        Start-Sleep -Seconds 2
        $tailIp = (& $tailscale ip -4 2>$null | Select-Object -First 1).Trim()
    } while ($tailIp -notmatch '^100\.' -and (Get-Date) -lt $deadline)
}
if ($tailIp -notmatch '^100\.') { throw 'Accesso Tailscale non completato entro quattro minuti. Riapri la configurazione automatica.' }

$installRoot = Join-Path $env:ProgramData 'VargaRemote'
$agentPath = Join-Path $installRoot 'VargaRemote-PowerAgent.ps1'
$configPath = Join-Path $installRoot 'power-agent.json'
New-Item $installRoot -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'VargaRemote-PowerAgent.ps1') $agentPath -Force

$token = $null
$rustDeskPassword = $null
if (Test-Path $configPath) {
    try {
        $existingConfig = Get-Content $configPath -Raw | ConvertFrom-Json
        $token = [string]$existingConfig.token
        $rustDeskPassword = [string]$existingConfig.rustDeskPassword
    }
    catch { }
}
if (-not $token) {
    $random = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($random)
    $token = [Convert]::ToBase64String($random)
}
if (-not $rustDeskPassword) {
    $passwordBytes = New-Object byte[] 18
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($passwordBytes)
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#_-'
    $rustDeskPassword = -join ($passwordBytes | ForEach-Object { $alphabet[[int]$_ % $alphabet.Length] })
}
[PSCustomObject]@{ port = 47832; token = $token; rustDeskPassword = $rustDeskPassword } |
    ConvertTo-Json | Set-Content $configPath -Encoding UTF8

& icacls.exe $installRoot /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null

# Configura RustDesk per accesso non presidiato e avvio prima del login.
$rustDesk = if (Get-Command Get-VargaRemoteRustDeskPath -ErrorAction SilentlyContinue) { Get-VargaRemoteRustDeskPath } else { $null }
if (-not $rustDesk) { throw 'RustDesk non trovato: installalo prima di preparare l accesso permanente.' }
$rustDeskService = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
if (-not $rustDeskService) {
    Start-Process -FilePath $rustDesk -ArgumentList @('--install-service') -Wait | Out-Null
    Start-Sleep -Seconds 3
    $rustDeskService = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
}
if (-not $rustDeskService) { throw 'Servizio RustDesk non installato.' }
Set-Service -Name $rustDeskService.Name -StartupType Automatic
if ($rustDeskService.Status -ne 'Running') { Start-Service -Name $rustDeskService.Name }
& $rustDesk --password $rustDeskPassword | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Impostazione della password permanente RustDesk non riuscita.' }

$tailscaleService = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
if ($tailscaleService) {
    Set-Service -Name $tailscaleService.Name -StartupType Automatic
    if ($tailscaleService.Status -ne 'Running') { Start-Service -Name $tailscaleService.Name }
}

$taskName = 'Varga Remote Power Agent'
$taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""
& schtasks.exe /Create /TN $taskName /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $taskCommand /F | Out-Null

Get-NetFirewallRule -DisplayName 'Varga Remote Power Agent (Tailscale)' -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'Varga Remote Power Agent (Tailscale)' -Direction Inbound `
    -Action Allow -Protocol TCP -LocalPort 47832 -RemoteAddress '100.64.0.0/10' -Profile Any | Out-Null
& schtasks.exe /Run /TN $taskName | Out-Null

if ($RefreshOnly) {
    Write-Host 'Power Agent aggiornato e riavviato.' -ForegroundColor Green
    exit 0
}

Write-Host ''
Write-Host 'AGENTE INSTALLATO' -ForegroundColor Green
Write-Host "Indirizzo Power Agent: http://${tailIp}:47832"
Write-Host "Token: $token"
Write-Host 'Conserva il token in modo sicuro: serve sul PC di controllo.' -ForegroundColor Yellow
$payload = [PSCustomObject]@{
    version = 2
    powerUrl = "http://${tailIp}:47832"
    token = $token
    computerName = $env:COMPUTERNAME
    rustDeskId = ''
    rustDeskPassword = $rustDeskPassword
    permanent = $true
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
}
if (Get-Command Get-VargaRemoteRustDeskPath -ErrorAction SilentlyContinue) {
    $rustDesk = Get-VargaRemoteRustDeskPath
    if ($rustDesk) { $payload.rustDeskId = (& $rustDesk --get-id 2>$null | Out-String).Trim() }
}
$payloadBytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress))
$accessData = 'VRE1:' + [Convert]::ToBase64String($payloadBytes)
try {
    Set-Clipboard -Value $accessData
    Write-Host 'Configurazione automatica copiata negli appunti.' -ForegroundColor Cyan
}
catch { }
Write-Host ''
if (-not $Automatic) {
    [void](Read-Host 'Premi INVIO soltanto dopo aver copiato i dati')
}
