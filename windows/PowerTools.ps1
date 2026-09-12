Set-StrictMode -Version Latest

function Get-VargaNetworkProfile {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
    if (-not $route) { return $null }

    $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
    $ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
    $ethernet = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Status -ne 'Disabled' -and
            ($_.Name -match '(?i)Ethernet' -or $_.InterfaceDescription -match '(?i)Ethernet|Gigabit|2\.5GbE|5GbE|10GbE|PCIe.*Controller|LAN')
        } |
        Sort-Object @{Expression={ if ($_.Status -eq 'Up') { 0 } else { 1 } }}, ifIndex |
        Select-Object -First 1

    [PSCustomObject]@{
        Gateway = [string]$route.NextHop
        LocalIp = if ($ip) { [string]$ip.IPAddress } else { '' }
        ActiveAdapter = if ($adapter) { [string]$adapter.Name } else { '' }
        ActiveMac = if ($adapter) { [string]$adapter.MacAddress } else { '' }
        EthernetName = if ($ethernet) { [string]$ethernet.Name } else { '' }
        EthernetMac = if ($ethernet) { [string]$ethernet.MacAddress } else { '' }
    }
}

function Get-VargaRouterInfo {
    param([string]$DatabasePath)
    $network = Get-VargaNetworkProfile
    if (-not $network) { throw 'Gateway Internet non rilevato.' }

    $manufacturer = ''
    $model = ''
    $friendlyName = ''
    $client = $null
    try {
        $client = New-Object Net.Sockets.UdpClient
        $client.Client.ReceiveTimeout = 2500
        $client.Connect('239.255.255.250', 1900)
        $request = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 1`r`nST: upnp:rootdevice`r`n`r`n"
        $bytes = [Text.Encoding]::ASCII.GetBytes($request)
        [void]$client.Send($bytes, $bytes.Length)
        $remote = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
        $response = [Text.Encoding]::ASCII.GetString($client.Receive([ref]$remote))
        $locationLine = ($response -split "`r?`n" | Where-Object { $_ -match '^LOCATION:' } | Select-Object -First 1)
        if ($locationLine) {
            $location = ($locationLine -replace '^LOCATION:\s*', '').Trim()
            [xml]$description = (Invoke-WebRequest -Uri $location -UseBasicParsing -TimeoutSec 3).Content
            $device = $description.root.device
            $manufacturer = [string]$device.manufacturer
            $model = [string]$device.modelName
            if (-not $model) { $model = [string]$device.modelNumber }
            $friendlyName = [string]$device.friendlyName
        }
    }
    catch { }
    finally { if ($client) { $client.Close() } }

    $profile = $null
    if ($DatabasePath -and (Test-Path $DatabasePath)) {
        try {
            $database = @(Get-Content $DatabasePath -Raw | ConvertFrom-Json)
            $haystack = "$manufacturer $model $friendlyName"
            $profile = $database | Where-Object {
                $haystack -match [regex]::Escape([string]$_.match)
            } | Select-Object -First 1
        }
        catch { }
    }

    [PSCustomObject]@{
        Gateway = $network.Gateway
        LocalIp = $network.LocalIp
        Manufacturer = $manufacturer
        Model = $model
        FriendlyName = $friendlyName
        EthernetMac = $network.EthernetMac
        Profile = $profile
    }
}

function Send-VargaWakeOnLan {
    param(
        [Parameter(Mandatory)][string]$MacAddress,
        [string]$Broadcast = '255.255.255.255',
        [int]$Port = 9
    )
    $clean = $MacAddress -replace '[^A-Fa-f0-9]', ''
    if ($clean.Length -ne 12) { throw 'Indirizzo MAC non valido.' }
    $mac = New-Object byte[] 6
    for ($i = 0; $i -lt 6; $i++) { $mac[$i] = [Convert]::ToByte($clean.Substring($i * 2, 2), 16) }
    $packet = New-Object byte[] 102
    for ($i = 0; $i -lt 6; $i++) { $packet[$i] = 0xFF }
    for ($block = 0; $block -lt 16; $block++) {
        [Array]::Copy($mac, 0, $packet, 6 + ($block * 6), 6)
    }
    $udp = New-Object Net.Sockets.UdpClient
    try {
        $udp.EnableBroadcast = $true
        [void]$udp.Send($packet, $packet.Length, $Broadcast, $Port)
    }
    finally { $udp.Close() }
}

function Invoke-VargaWindowsPower {
    param(
        [Parameter(Mandatory)][ValidateSet('shutdown','restart','cancel')][string]$Action,
        [Parameter(Mandatory)][string]$Computer,
        [int]$DelaySeconds = 60
    )
    $target = "\\$Computer"
    $arguments = switch ($Action) {
        'shutdown' { @('/m', $target, '/s', '/t', $DelaySeconds, '/c', '"Spegnimento richiesto da Varga Remote"') }
        'restart'  { @('/m', $target, '/r', '/t', $DelaySeconds, '/c', '"Riavvio richiesto da Varga Remote"') }
        'cancel'   { @('/m', $target, '/a') }
    }
    $process = Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw 'Comando rifiutato. Serve la stessa rete/VPN e autorizzazione Windows per lo spegnimento remoto.'
    }
}
