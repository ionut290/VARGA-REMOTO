#requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath = "$env:ProgramData\VargaRemote\power-agent.json")

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $ConfigPath)) { throw "Configurazione non trovata: $ConfigPath" }
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$port = [int]$config.port
$token = [string]$config.token
if ($port -lt 1024 -or $port -gt 65535 -or $token.Length -lt 32) { throw 'Configurazione agente non valida.' }

function Test-VargaTailnetAddress([string]$Address) {
    if ($Address -eq '127.0.0.1' -or $Address -eq '::1') { return $true }
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork') { return $false }
    $bytes = $ip.GetAddressBytes()
    return $bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127
}

function Write-VargaJsonResponse($Context, [int]$StatusCode, [hashtable]$Payload) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress))
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = 'application/json; charset=utf-8'
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://+:$port/")
$listener.Start()

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $remoteAddress = [string]$context.Request.RemoteEndPoint.Address
            if (-not (Test-VargaTailnetAddress $remoteAddress)) {
                Write-VargaJsonResponse $context 403 @{ ok = $false; error = 'Rete non autorizzata.' }
                continue
            }
            if ([string]$context.Request.Headers['Authorization'] -cne "Bearer $token") {
                Write-VargaJsonResponse $context 401 @{ ok = $false; error = 'Token non valido.' }
                continue
            }
            if ($context.Request.HttpMethod -ne 'POST' -or $context.Request.Url.AbsolutePath -ne '/power') {
                Write-VargaJsonResponse $context 404 @{ ok = $false; error = 'Comando non disponibile.' }
                continue
            }
            $reader = New-Object IO.StreamReader($context.Request.InputStream, $context.Request.ContentEncoding)
            try { $body = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
            $action = [string]$body.action
            $delay = [Math]::Max(0, [Math]::Min(600, [int]$body.delaySeconds))
            $arguments = switch ($action) {
                'shutdown' { @('/s', '/t', $delay, '/c', '"Spegnimento richiesto da Varga Remote"') }
                'restart'  { @('/r', '/t', $delay, '/c', '"Riavvio richiesto da Varga Remote"') }
                'cancel'   { @('/a') }
                default { $null }
            }
            if (-not $arguments) {
                Write-VargaJsonResponse $context 400 @{ ok = $false; error = 'Azione non valida.' }
                continue
            }
            $process = Start-Process "$env:SystemRoot\System32\shutdown.exe" -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
            if ($process.ExitCode -ne 0) {
                Write-VargaJsonResponse $context 500 @{ ok = $false; error = "shutdown.exe: $($process.ExitCode)" }
                continue
            }
            Write-VargaJsonResponse $context 200 @{ ok = $true; action = $action; delaySeconds = $delay }
        }
        catch {
            try { Write-VargaJsonResponse $context 500 @{ ok = $false; error = $_.Exception.Message } } catch { }
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
