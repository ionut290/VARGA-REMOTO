#requires -Version 5.1
Set-StrictMode -Version Latest

$script:VargaExternalConfigPath = Join-Path (Join-Path $env:APPDATA 'VargaRemote') 'external-access.json'

function Protect-VargaExternalToken {
    param([Parameter(Mandatory)][string]$Token)
    $secure = ConvertTo-SecureString -String $Token -AsPlainText -Force
    return ConvertFrom-SecureString -SecureString $secure
}

function Unprotect-VargaExternalToken {
    param([Parameter(Mandatory)][string]$ProtectedToken)
    $secure = ConvertTo-SecureString -String $ProtectedToken
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Get-VargaExternalAccessEntries {
    if (-not (Test-Path $script:VargaExternalConfigPath)) { return @() }
    try { return @((Get-Content $script:VargaExternalConfigPath -Raw | ConvertFrom-Json)) }
    catch { return @() }
}

function Get-VargaExternalAccessConfig {
    param([Parameter(Mandatory)][string]$DeviceId)
    return Get-VargaExternalAccessEntries |
        Where-Object { [string]$_.deviceId -eq $DeviceId } |
        Select-Object -First 1
}

function Save-VargaExternalAccessConfig {
    param(
        [Parameter(Mandatory)][string]$DeviceId,
        [string]$RelayUrl = '',
        [string]$PowerUrl = '',
        [Parameter(Mandatory)][string]$Token,
        [string]$RustDeskPassword = ''
    )
    if (-not $RelayUrl -and -not $PowerUrl) { throw 'Nessun servizio esterno rilevato.' }
    foreach ($value in @($RelayUrl, $PowerUrl) | Where-Object { $_ }) {
        $uri = $null
        if (-not [Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'http') {
            throw 'Gli indirizzi devono iniziare con http:// e usare un IP Tailscale 100.x.x.x.'
        }
        if (-not $uri.Host.StartsWith('100.')) {
            throw 'Per sicurezza sono ammessi soltanto indirizzi Tailscale 100.x.x.x.'
        }
    }
    if ($Token.Length -lt 32) { throw 'Il token deve contenere almeno 32 caratteri.' }

    $directory = Split-Path $script:VargaExternalConfigPath -Parent
    New-Item -Path $directory -ItemType Directory -Force | Out-Null
    $entries = @(Get-VargaExternalAccessEntries | Where-Object { [string]$_.deviceId -ne $DeviceId })
    $entries += [PSCustomObject]@{
        deviceId = $DeviceId
        relayUrl = $RelayUrl.TrimEnd('/')
        powerUrl = $PowerUrl.TrimEnd('/')
        protectedToken = Protect-VargaExternalToken -Token $Token
        protectedRustDeskPassword = $(if ($RustDeskPassword) { Protect-VargaExternalToken -Token $RustDeskPassword } else { '' })
        permanent = $true
        updatedAt = (Get-Date).ToString('o')
    }
    @($entries) | ConvertTo-Json -Depth 5 | Set-Content $script:VargaExternalConfigPath -Encoding UTF8
}

function ConvertTo-VargaExternalPairingCode {
    param(
        [Parameter(Mandatory)][string]$PowerUrl,
        [Parameter(Mandatory)][string]$Token,
        [string]$ComputerName = $env:COMPUTERNAME,
        [string]$RustDeskId = '',
        [string]$RustDeskPassword = ''
    )
    $payload = [PSCustomObject]@{
        version = 2
        powerUrl = $PowerUrl
        token = $Token
        computerName = $ComputerName
        rustDeskId = $RustDeskId
        rustDeskPassword = $RustDeskPassword
        permanent = $true
        createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress))
    return 'VRE1:' + [Convert]::ToBase64String($bytes)
}

function ConvertFrom-VargaExternalPairingCode {
    param([Parameter(Mandatory)][string]$Code)
    $clean = $Code.Trim()
    if (-not $clean.StartsWith('VRE1:')) { throw 'Negli appunti non c e una configurazione automatica Varga Remote.' }
    try {
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($clean.Substring(5)))
        $payload = $json | ConvertFrom-Json
    }
    catch { throw 'Configurazione automatica danneggiata o non valida.' }
    if ([int]$payload.version -notin @(1, 2) -or -not [string]$payload.powerUrl -or ([string]$payload.token).Length -lt 32) {
        throw 'Configurazione automatica incompleta.'
    }
    return $payload
}

function Get-VargaTailscalePath {
    return @(
        "$env:ProgramFiles\Tailscale\tailscale.exe",
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

function Find-VargaRelay {
    param([Parameter(Mandatory)][string]$Token)
    $tailscale = Get-VargaTailscalePath
    if (-not $tailscale) { return '' }
    try { $status = (& $tailscale status --json 2>$null | Out-String) | ConvertFrom-Json }
    catch { return '' }
    $addresses = @()
    if ($status.Peer) {
        foreach ($peerProperty in $status.Peer.PSObject.Properties) {
            $peer = $peerProperty.Value
            $addresses += @($peer.TailscaleIPs | Where-Object { [string]$_ -match '^100\.' })
        }
    }
    $headers = @{ Authorization = "Bearer $Token" }
    foreach ($address in @($addresses | Select-Object -Unique)) {
        $url = "http://${address}:47831"
        try {
            $health = Invoke-RestMethod -Uri "$url/health" -Headers $headers -TimeoutSec 2
            if ($health.ok -and [string]$health.service -eq 'VargaRelay') { return $url }
        }
        catch { }
    }
    return ''
}

function Remove-VargaExternalAccessConfig {
    param([Parameter(Mandatory)][string]$DeviceId)
    $entries = @(Get-VargaExternalAccessEntries | Where-Object { [string]$_.deviceId -ne $DeviceId })
    @($entries) | ConvertTo-Json -Depth 5 | Set-Content $script:VargaExternalConfigPath -Encoding UTF8
}

function Invoke-VargaExternalRequest {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][ValidateSet('wake','power')][string]$Endpoint,
        [Parameter(Mandatory)][hashtable]$Body
    )
    $baseUrl = if ($Endpoint -eq 'wake') { [string]$Config.relayUrl } else { [string]$Config.powerUrl }
    if (-not $baseUrl) { throw 'Servizio esterno non ancora configurato.' }
    if ($Endpoint -eq 'power') {
        $targetUri = [Uri]$baseUrl
        $tailscale = Get-VargaTailscalePath
        if ($tailscale) {
            $localTailIps = @(& $tailscale ip -4 2>$null | ForEach-Object { ([string]$_).Trim() })
            if ($localTailIps -contains $targetUri.Host) {
                throw 'BLOCCATO: questo indirizzo appartiene al PC che stai usando. Prepara e importa la configurazione dal PC remoto, non da questo PC.'
            }
        }
    }
    $token = Unprotect-VargaExternalToken -ProtectedToken ([string]$Config.protectedToken)
    $headers = @{ Authorization = "Bearer $token" }
    try {
        return Invoke-RestMethod -Uri "$baseUrl/$Endpoint" -Method Post -Headers $headers `
            -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Compress) -TimeoutSec 12
    }
    catch {
        $detail = ''
        try {
            $response = $_.Exception.Response
            if ($response) {
                $reader = New-Object IO.StreamReader($response.GetResponseStream())
                try {
                    $errorPayload = $reader.ReadToEnd() | ConvertFrom-Json
                    $detail = [string]$errorPayload.error
                }
                finally { $reader.Dispose() }
            }
        }
        catch { }
        if ($detail) { throw "Power Agent: $detail" }
        throw
    }
}

function Invoke-VargaExternalWake {
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$MacAddress)
    return Invoke-VargaExternalRequest -Config $Config -Endpoint wake -Body @{ mac = $MacAddress }
}

function Invoke-VargaExternalPower {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][ValidateSet('shutdown','restart','cancel')][string]$Action,
        [int]$DelaySeconds = 60
    )
    return Invoke-VargaExternalRequest -Config $Config -Endpoint power -Body @{
        action = $Action
        delaySeconds = $DelaySeconds
    }
}
