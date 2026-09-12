#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Esegui questo file come amministratore sul PC da controllare.'
}

$tailscale = @(
    "$env:ProgramFiles\Tailscale\tailscale.exe",
    "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $tailscale) {
    throw 'Tailscale non trovato. Installalo e collegalo al tuo account, poi riesegui questo file.'
}
$tailIp = (& $tailscale ip -4 2>$null | Select-Object -First 1).Trim()
if ($tailIp -notmatch '^100\.') { throw 'Tailscale non e ancora collegato. Apri Tailscale, accedi e riprova.' }

$installRoot = Join-Path $env:ProgramData 'VargaRemote'
$agentPath = Join-Path $installRoot 'VargaRemote-PowerAgent.ps1'
$configPath = Join-Path $installRoot 'power-agent.json'
New-Item $installRoot -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'VargaRemote-PowerAgent.ps1') $agentPath -Force

$token = $null
if (Test-Path $configPath) {
    try { $token = [string](Get-Content $configPath -Raw | ConvertFrom-Json).token } catch { }
}
if (-not $token) {
    $random = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($random)
    $token = [Convert]::ToBase64String($random)
}
[PSCustomObject]@{ port = 47832; token = $token } |
    ConvertTo-Json | Set-Content $configPath -Encoding UTF8

& icacls.exe $installRoot /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null

$taskName = 'Varga Remote Power Agent'
$taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""
& schtasks.exe /Create /TN $taskName /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $taskCommand /F | Out-Null

Get-NetFirewallRule -DisplayName 'Varga Remote Power Agent (Tailscale)' -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'Varga Remote Power Agent (Tailscale)' -Direction Inbound `
    -Action Allow -Protocol TCP -LocalPort 47832 -RemoteAddress '100.64.0.0/10' -Profile Any | Out-Null
& schtasks.exe /Run /TN $taskName | Out-Null

Write-Host ''
Write-Host 'AGENTE INSTALLATO' -ForegroundColor Green
Write-Host "Indirizzo Power Agent: http://${tailIp}:47832"
Write-Host "Token: $token"
Write-Host 'Conserva il token in modo sicuro: serve sul PC di controllo.' -ForegroundColor Yellow
$accessData = @(
    "Indirizzo Power Agent: http://${tailIp}:47832",
    "Token: $token"
) -join [Environment]::NewLine
try {
    Set-Clipboard -Value $accessData
    Write-Host 'Indirizzo e token copiati negli appunti.' -ForegroundColor Cyan
}
catch { }
Write-Host ''
[void](Read-Host 'Premi INVIO soltanto dopo aver copiato i dati')
