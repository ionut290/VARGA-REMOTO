#requires -Version 5.1
Set-StrictMode -Version Latest

# Smart Wake does not open router ports and does not store router/RustDesk passwords.
# It detects the safest usable path at run time: same LAN, routed VPN, or a
# previously verified Wake-on-WAN profile. Router/AMT candidates are reported as
# setup-required until Varga Remote can actually prove they are usable.

function Get-VargaObjectValue {
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Test-VargaPrivateIPv4 {
    param([string]$Address)
    if ([string]::IsNullOrWhiteSpace($Address)) { return $false }
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$ip)) { return $false }
    $bytes = $ip.GetAddressBytes()
    if ($bytes.Length -ne 4) { return $false }

    # RFC1918, link-local and shared CGNAT space are treated as non-public.
    if ($bytes[0] -eq 10) { return $true }
    if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return $true }
    if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { return $true }
    if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return $true }
    if ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) { return $true }
    if ($bytes[0] -eq 127) { return $true }
    return $false
}

function Get-VargaIPv4Broadcast {
    param([string]$Address, [int]$PrefixLength = 24)
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$ip)) { return '' }
    if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) { return '' }
    $bytes = $ip.GetAddressBytes()
    if ($bytes.Length -ne 4) { return '' }

    # Byte-by-byte calculation avoids signed/unsigned overflow differences
    # between Windows PowerShell/.NET versions.
    $out = New-Object byte[] 4
    for ($index = 0; $index -lt 4; $index++) {
        $remaining = $PrefixLength - ($index * 8)
        if ($remaining -ge 8) { $maskByte = 255 }
        elseif ($remaining -le 0) { $maskByte = 0 }
        else { $maskByte = 256 - [int][Math]::Pow(2, (8 - $remaining)) }
        $hostByte = 255 - $maskByte
        $out[$index] = [byte](([int]$bytes[$index]) -bor $hostByte)
    }
    return ([Net.IPAddress]::new($out)).ToString()
}

function Get-VargaGatewayMac {
    param([string]$Gateway)
    if ([string]::IsNullOrWhiteSpace($Gateway)) { return '' }
    try {
        [void](Test-Connection -ComputerName $Gateway -Count 1 -Quiet -ErrorAction SilentlyContinue)
    }
    catch { }
    try {
        $neighbor = Get-NetNeighbor -IPAddress $Gateway -ErrorAction SilentlyContinue |
            Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -notmatch '^00[-:]00[-:]00[-:]00[-:]00[-:]00$' } |
            Select-Object -First 1
        if ($neighbor) { return ([string]$neighbor.LinkLayerAddress).ToUpperInvariant() }
    }
    catch { }
    try {
        $line = arp.exe -a $Gateway 2>$null | Select-String -Pattern '([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}' | Select-Object -First 1
        if ($line -and $line.Matches.Count -gt 0) { return $line.Matches[0].Value.ToUpperInvariant() }
    }
    catch { }
    return ''
}

function Get-VargaXmlNodeText {
    param([xml]$Document, [string]$LocalName)
    try {
        $node = $Document.SelectSingleNode("//*[local-name()='$LocalName']")
        if ($node) { return [string]$node.InnerText }
    }
    catch { }
    return ''
}

function Join-VargaUri {
    param([string]$BaseUri, [string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative)) { return '' }
    try {
        $candidate = $null
        if ([Uri]::TryCreate($Relative, [UriKind]::Absolute, [ref]$candidate)) { return $candidate.AbsoluteUri }
        $base = [Uri]::new($BaseUri)
        return ([Uri]::new($base, $Relative)).AbsoluteUri
    }
    catch { return '' }
}

function Get-VargaSsdpRouterCandidate {
    param([Parameter(Mandatory)][string]$Gateway, [int]$TimeoutMs = 2600)
    $client = $null
    $results = @()
    try {
        $client = New-Object Net.Sockets.UdpClient
        $client.Client.ReceiveTimeout = 450
        $client.MulticastLoopback = $false
        $request = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 1`r`nST: ssdp:all`r`n`r`n"
        $bytes = [Text.Encoding]::ASCII.GetBytes($request)
        [void]$client.Send($bytes, $bytes.Length, '239.255.255.250', 1900)
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while ($watch.ElapsedMilliseconds -lt $TimeoutMs) {
            try {
                $remote = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
                $response = [Text.Encoding]::ASCII.GetString($client.Receive([ref]$remote))
                $lines = $response -split "`r?`n"
                $locationLine = $lines | Where-Object { $_ -match '^LOCATION\s*:' } | Select-Object -First 1
                if (-not $locationLine) { continue }
                $location = ($locationLine -replace '^LOCATION\s*:\s*', '').Trim()
                if (-not $location) { continue }
                $serverLine = $lines | Where-Object { $_ -match '^SERVER\s*:' } | Select-Object -First 1
                $stLine = $lines | Where-Object { $_ -match '^ST\s*:' } | Select-Object -First 1
                $server = if ($serverLine) { ($serverLine -replace '^SERVER\s*:\s*', '').Trim() } else { '' }
                $searchTarget = if ($stLine) { ($stLine -replace '^ST\s*:\s*', '').Trim() } else { '' }
                $locationHost = ''
                try { $locationHost = ([Uri]::new($location)).Host } catch { }
                $score = 0
                if ($locationHost -eq $Gateway) { $score += 100 }
                if ($response -match 'InternetGatewayDevice|WANDevice|WANConnectionDevice') { $score += 30 }
                if ($searchTarget -match 'InternetGatewayDevice|WANDevice|WANConnectionDevice') { $score += 20 }
                $results += [PSCustomObject]@{
                    Location = $location
                    LocationHost = $locationHost
                    Server = $server
                    SearchTarget = $searchTarget
                    Score = $score
                }
            }
            catch [Net.Sockets.SocketException] { }
            catch { }
        }
    }
    catch { }
    finally { if ($client) { $client.Close() } }

    $seen = @{}
    $unique = @()
    foreach ($entry in ($results | Sort-Object Score -Descending)) {
        if (-not $seen.ContainsKey([string]$entry.Location)) {
            $seen[[string]$entry.Location] = $true
            $unique += $entry
        }
    }

    foreach ($entry in $unique) {
        try {
            [xml]$description = (Invoke-WebRequest -Uri $entry.Location -UseBasicParsing -TimeoutSec 3).Content
            $manufacturer = Get-VargaXmlNodeText $description 'manufacturer'
            $model = Get-VargaXmlNodeText $description 'modelName'
            if (-not $model) { $model = Get-VargaXmlNodeText $description 'modelNumber' }
            $friendlyName = Get-VargaXmlNodeText $description 'friendlyName'
            $presentationUrl = Get-VargaXmlNodeText $description 'presentationURL'

            $serviceNodes = @($description.SelectNodes("//*[local-name()='service']"))
            $serviceType = ''
            $controlUrl = ''
            foreach ($service in $serviceNodes) {
                $typeNode = $service.SelectSingleNode("./*[local-name()='serviceType']")
                $controlNode = $service.SelectSingleNode("./*[local-name()='controlURL']")
                if ($typeNode -and $controlNode -and $typeNode.InnerText -match 'WANIPConnection|WANPPPConnection') {
                    $serviceType = [string]$typeNode.InnerText
                    $controlUrl = Join-VargaUri $entry.Location ([string]$controlNode.InnerText)
                    break
                }
            }

            $score = [int]$entry.Score
            if ($manufacturer -or $model -or $friendlyName) { $score += 15 }
            if ($serviceType) { $score += 40 }
            return [PSCustomObject]@{
                Found = $true
                DescriptionUrl = $entry.Location
                LocationHost = $entry.LocationHost
                Manufacturer = $manufacturer
                Model = $model
                FriendlyName = $friendlyName
                Server = $entry.Server
                PresentationUrl = $presentationUrl
                ServiceType = $serviceType
                ControlUrl = $controlUrl
                Score = $score
            }
        }
        catch { }
    }

    return [PSCustomObject]@{
        Found = $false
        DescriptionUrl = ''
        LocationHost = ''
        Manufacturer = ''
        Model = ''
        FriendlyName = ''
        Server = ''
        PresentationUrl = ''
        ServiceType = ''
        ControlUrl = ''
        Score = 0
    }
}

function Get-VargaGatewayHttpFingerprint {
    param([string]$Gateway)
    if ([string]::IsNullOrWhiteSpace($Gateway)) { return '' }
    foreach ($scheme in @('http', 'https')) {
        try {
            $response = Invoke-WebRequest -Uri ("{0}://{1}/" -f $scheme, $Gateway) -UseBasicParsing -TimeoutSec 2 -MaximumRedirection 2 -ErrorAction Stop
            $title = ''
            if ($response.Content -match '(?is)<title[^>]*>(.*?)</title>') {
                $title = (($matches[1] -replace '<[^>]+>', ' ') -replace '\s+', ' ').Trim()
            }
            $server = ''
            if ($response.Headers -and $response.Headers['Server']) { $server = [string]$response.Headers['Server'] }
            $fingerprint = ("$title $server").Trim()
            if ($fingerprint) { return $fingerprint }
        }
        catch { }
    }
    return ''
}

function Get-VargaUpnpExternalIp {
    param($Candidate)
    $serviceType = [string](Get-VargaObjectValue $Candidate 'ServiceType' '')
    $controlUrl = [string](Get-VargaObjectValue $Candidate 'ControlUrl' '')
    if (-not $serviceType -or -not $controlUrl) { return '' }
    try {
        $action = "$serviceType#GetExternalIPAddress"
        $body = @"
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:GetExternalIPAddress xmlns:u="$serviceType" />
  </s:Body>
</s:Envelope>
"@
        $response = Invoke-WebRequest -Uri $controlUrl -Method Post -UseBasicParsing -TimeoutSec 4 -ContentType 'text/xml; charset="utf-8"' -Headers @{ SOAPAction = ('"{0}"' -f $action) } -Body $body
        if ($response.Content -match '<NewExternalIPAddress>([^<]+)</NewExternalIPAddress>') { return $matches[1].Trim() }
    }
    catch { }
    return ''
}

function Get-VargaPublicIp {
    try {
        $result = Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 4
        if ($result -and $result.ip) { return [string]$result.ip }
    }
    catch { }
    return ''
}

function Test-VargaTcpPort {
    param([string]$HostName = '127.0.0.1', [Parameter(Mandatory)][int]$Port, [int]$TimeoutMs = 350)
    $client = New-Object Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($async)
        return $client.Connected
    }
    catch { return $false }
    finally { $client.Close() }
}

function Test-VargaVpnName {
    param([string]$Name, [string]$Description)
    $text = "$Name $Description"
    return ($text -match '(?i)WireGuard|OpenVPN|Tailscale|ZeroTier|VPN|TAP|TUN|Wintun|NordLynx')
}

function Get-VargaVpnAdapters {
    try {
        return @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq 'Up' -and (Test-VargaVpnName -Name ([string]$_.Name) -Description ([string]$_.InterfaceDescription))
        } | ForEach-Object { [string]$_.Name })
    }
    catch { return @() }
}

function Get-VargaRouteToTarget {
    param([string]$TargetAddress)
    if ([string]::IsNullOrWhiteSpace($TargetAddress)) { return $null }
    try {
        $route = Find-NetRoute -RemoteIPAddress $TargetAddress -ErrorAction Stop | Select-Object -First 1
        if (-not $route) { return $null }
        $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
        $name = if ($adapter) { [string]$adapter.Name } else { '' }
        $description = if ($adapter) { [string]$adapter.InterfaceDescription } else { '' }
        return [PSCustomObject]@{
            InterfaceIndex = [int]$route.InterfaceIndex
            InterfaceName = $name
            InterfaceDescription = $description
            NextHop = [string]$route.NextHop
            IsVpn = (Test-VargaVpnName -Name $name -Description $description)
        }
    }
    catch { return $null }
}

function Get-VargaAmtCapability {
    $serviceFound = $false
    $meiFound = $false
    try {
        $services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -eq 'LMS' -or $_.DisplayName -match 'Intel.*Management.*Security|Local Management Service'
        })
        $serviceFound = ($services.Count -gt 0)
    }
    catch { }
    try {
        if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
            $meiFound = (@(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
                $_.FriendlyName -match 'Intel.*Management Engine|Intel.*MEI'
            }).Count -gt 0)
        }
    }
    catch { }

    $port16992 = Test-VargaTcpPort -HostName '127.0.0.1' -Port 16992
    $port16993 = Test-VargaTcpPort -HostName '127.0.0.1' -Port 16993
    [PSCustomObject]@{
        ServiceFound = $serviceFound
        ManagementEngineFound = $meiFound
        Port16992 = $port16992
        Port16993 = $port16993
        HardwareCandidate = ($serviceFound -or $meiFound)
        LocalManagementAvailable = ($serviceFound -and ($port16992 -or $port16993))
        # Do not claim remote provisioning from local discovery alone.
        RemoteProvisioned = $false
    }
}

function Get-VargaEthernetAdapter {
    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -ne 'Disabled' -and (
                $_.Name -match '(?i)Ethernet' -or
                $_.InterfaceDescription -match '(?i)Ethernet|Gigabit|2\.5GbE|5GbE|10GbE|PCIe.*Controller|LAN'
            )
        } | Sort-Object @{Expression={ if ($_.Status -eq 'Up') { 0 } else { 1 } }}, ifIndex)
        if ($adapters.Count -gt 0) { return $adapters[0] }
    }
    catch { }
    return $null
}

function Get-VargaEthernetNetworkInfo {
    $adapter = Get-VargaEthernetAdapter
    if (-not $adapter) {
        return [PSCustomObject]@{ Ip = ''; PrefixLength = 0; Broadcast = ''; Gateway = '' }
    }
    $ipRecord = $null
    try {
        $ipRecord = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -and $_.IPAddress -notlike '169.254.*' } |
            Select-Object -First 1
    }
    catch { }
    if (-not $ipRecord) {
        return [PSCustomObject]@{ Ip = ''; PrefixLength = 0; Broadcast = ''; Gateway = '' }
    }
    $gateway = ''
    try {
        $route = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric | Select-Object -First 1
        if ($route) { $gateway = [string]$route.NextHop }
    }
    catch { }
    $prefix = [int]$ipRecord.PrefixLength
    $ip = [string]$ipRecord.IPAddress
    return [PSCustomObject]@{
        Ip = $ip
        PrefixLength = $prefix
        Broadcast = Get-VargaIPv4Broadcast -Address $ip -PrefixLength $prefix
        Gateway = $gateway
    }
}

function Get-VargaWakeCapability {
    $adapter = Get-VargaEthernetAdapter
    if (-not $adapter) {
        return [PSCustomObject]@{
            AdapterFound = $false
            Name = ''
            Description = ''
            Mac = ''
            Status = ''
            WakeOnMagicPacket = 'Unknown'
            WakeArmed = $false
            AdvancedWake = @()
            SupportsWake = $false
        }
    }

    $magic = 'Unknown'
    try {
        $pm = Get-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction Stop
        if ($pm.PSObject.Properties['WakeOnMagicPacket']) { $magic = [string]$pm.WakeOnMagicPacket }
    }
    catch { }

    $armed = $false
    try {
        $armedText = (& powercfg.exe /devicequery wake_armed 2>$null | Out-String)
        if ($armedText -and ($armedText -match [regex]::Escape([string]$adapter.InterfaceDescription) -or $armedText -match [regex]::Escape([string]$adapter.Name))) {
            $armed = $true
        }
    }
    catch { }

    $advanced = @()
    try {
        $advanced = @(Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -match '(?i)Wake.*Magic|Shutdown.*Wake|Wake.*LAN|Magic Packet'
        } | ForEach-Object { "{0}: {1}" -f $_.DisplayName, $_.DisplayValue })
    }
    catch { }

    # Unknown does not prove support. Require at least an explicit power setting,
    # an armed device, or an advanced driver property.
    $supports = (($magic -match '(?i)Enabled') -or $armed -or ($advanced.Count -gt 0))
    [PSCustomObject]@{
        AdapterFound = $true
        Name = [string]$adapter.Name
        Description = [string]$adapter.InterfaceDescription
        Mac = [string]$adapter.MacAddress
        Status = [string]$adapter.Status
        WakeOnMagicPacket = $magic
        WakeArmed = $armed
        AdvancedWake = $advanced
        SupportsWake = $supports
    }
}

function Enable-VargaEthernetWake {
    $adapter = Get-VargaEthernetAdapter
    if (-not $adapter) {
        return [PSCustomObject]@{ Changed = $false; Message = 'Scheda Ethernet non rilevata.' }
    }

    $messages = @()
    $changed = $false
    try {
        if (Get-Command Set-NetAdapterPowerManagement -ErrorAction SilentlyContinue) {
            Set-NetAdapterPowerManagement -Name $adapter.Name -WakeOnMagicPacket Enabled -ErrorAction Stop | Out-Null
            $messages += 'Wake on Magic Packet abilitato in Windows.'
            $changed = $true
        }
    }
    catch { $messages += 'Windows non ha consentito la modifica Wake on Magic Packet.' }

    try {
        & powercfg.exe /deviceenablewake ([string]$adapter.InterfaceDescription) 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $messages += 'Permesso di riattivazione del dispositivo abilitato.'
            $changed = $true
        }
    }
    catch { }

    if ($messages.Count -eq 0) { $messages += 'Nessuna modifica automatica necessaria.' }
    return [PSCustomObject]@{ Changed = $changed; Message = ($messages -join ' ') }
}

function Get-VargaFastStartupState {
    try {
        $value = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction Stop).HiberbootEnabled
        return [PSCustomObject]@{ Known = $true; Enabled = ([int]$value -eq 1) }
    }
    catch { return [PSCustomObject]@{ Known = $false; Enabled = $false } }
}

function Get-VargaHibernateState {
    try {
        $text = (& powercfg.exe /a 2>$null | Out-String)
        $available = ($text -match '(?i)hibernate|ibernazione') -and ($text -notmatch '(?i)hibernate.*not available|ibernazione.*non disponibile')
        return [PSCustomObject]@{ Available = $available; Raw = $text.Trim() }
    }
    catch { return [PSCustomObject]@{ Available = $false; Raw = '' } }
}

function Find-VargaRouterDatabaseProfile {
    param([string]$DatabasePath, [string]$Haystack)
    if (-not $DatabasePath -or -not (Test-Path $DatabasePath)) { return $null }
    try {
        $database = @(Get-Content $DatabasePath -Raw | ConvertFrom-Json)
        foreach ($entry in $database) {
            $patterns = @(Get-VargaObjectValue $entry 'matches' @())
            if ($patterns.Count -eq 0) {
                $legacy = [string](Get-VargaObjectValue $entry 'match' '')
                if ($legacy) { $patterns = @($legacy) }
            }
            foreach ($matchText in $patterns) {
                if ($matchText -and $Haystack -match [regex]::Escape([string]$matchText)) { return $entry }
            }
        }
    }
    catch { }
    return $null
}

function Get-VargaSmartRouterInfo {
    param([string]$DatabasePath)
    $network = Get-VargaNetworkProfile
    if (-not $network) { throw 'Gateway Internet non rilevato.' }

    $gatewayMac = Get-VargaGatewayMac $network.Gateway
    $ssdp = Get-VargaSsdpRouterCandidate -Gateway $network.Gateway
    $httpFingerprint = Get-VargaGatewayHttpFingerprint -Gateway $network.Gateway
    $wanIp = Get-VargaUpnpExternalIp -Candidate $ssdp
    $publicIp = Get-VargaPublicIp

    $haystack = @(
        [string](Get-VargaObjectValue $ssdp 'Manufacturer' ''),
        [string](Get-VargaObjectValue $ssdp 'Model' ''),
        [string](Get-VargaObjectValue $ssdp 'FriendlyName' ''),
        [string](Get-VargaObjectValue $ssdp 'Server' ''),
        $httpFingerprint
    ) -join ' '
    $profile = Find-VargaRouterDatabaseProfile -DatabasePath $DatabasePath -Haystack $haystack

    $cgnat = $false
    $cgnatKnown = $false
    if ($wanIp) {
        $cgnatKnown = $true
        if (Test-VargaPrivateIPv4 $wanIp) { $cgnat = $true }
        elseif ($publicIp -and $wanIp -ne $publicIp) { $cgnat = $true }
    }

    $routerName = ("{0} {1} {2}" -f (Get-VargaObjectValue $ssdp 'Manufacturer' ''), (Get-VargaObjectValue $ssdp 'Model' ''), (Get-VargaObjectValue $ssdp 'FriendlyName' '')).Trim()
    if (-not $routerName) { $routerName = $httpFingerprint }
    if (-not $routerName) { $routerName = 'Modello non esposto dal router' }

    [PSCustomObject]@{
        Gateway = $network.Gateway
        GatewayMac = $gatewayMac
        Name = $routerName
        Manufacturer = [string](Get-VargaObjectValue $ssdp 'Manufacturer' '')
        Model = [string](Get-VargaObjectValue $ssdp 'Model' '')
        FriendlyName = [string](Get-VargaObjectValue $ssdp 'FriendlyName' '')
        HttpFingerprint = $httpFingerprint
        UpnpDetected = [bool](Get-VargaObjectValue $ssdp 'Found' $false)
        UpnpServiceType = [string](Get-VargaObjectValue $ssdp 'ServiceType' '')
        WanIp = $wanIp
        PublicIp = $publicIp
        CgnatKnown = $cgnatKnown
        Cgnat = $cgnat
        Profile = $profile
        # This is deliberately false until a future explicit verification step.
        WakeOnWanVerified = $false
    }
}

function Get-VargaSmartWakeRecommendation {
    param($Wake, $Router, $Amt)
    $routerRemote = ''
    $routerNote = ''
    $vpnPreferred = $false
    if ($Router) {
        $routerProfile = Get-VargaObjectValue $Router 'Profile' $null
        if ($routerProfile) {
            $routerRemote = [string](Get-VargaObjectValue $routerProfile 'remoteWake' '')
            $routerNote = [string](Get-VargaObjectValue $routerProfile 'note' '')
            $vpnPreferred = [bool](Get-VargaObjectValue $routerProfile 'vpnPreferred' $false)
        }
    }

    if ($Wake -and [bool](Get-VargaObjectValue $Wake 'SupportsWake' $false)) {
        if ($routerRemote -eq 'router-ui-or-vpn' -or $routerRemote -eq 'vpn-preferred' -or $vpnPreferred) {
            $reason = if ($routerNote) { $routerNote } else { 'Il router sembra adatto a una VPN con Wake-on-LAN.' }
            return [PSCustomObject]@{
                Method = 'ROUTER_VPN'
                Label = 'VPN router + Wake-on-LAN'
                Score = 95
                RemoteState = 'SETUP_REQUIRED'
                Reason = $reason
                Action = 'Configura una volta la VPN sul router. Poi ACCENDI rilevera automaticamente la rotta VPN e inviera il Magic Packet.'
            }
        }

        $cgnatKnown = if ($Router) { [bool](Get-VargaObjectValue $Router 'CgnatKnown' $false) } else { $false }
        $cgnat = if ($Router) { [bool](Get-VargaObjectValue $Router 'Cgnat' $false) } else { $false }
        $publicIp = if ($Router) { [string](Get-VargaObjectValue $Router 'PublicIp' '') } else { '' }
        if ($cgnatKnown -and (-not $cgnat) -and $publicIp) {
            return [PSCustomObject]@{
                Method = 'WAKE_ON_WAN_CANDIDATE'
                Label = 'Wake-on-WAN / VPN'
                Score = 80
                RemoteState = 'SETUP_REQUIRED'
                Reason = 'La rete dispone di un IP WAN pubblico, ma Varga Remote non apre automaticamente porte UDP sul router.'
                Action = 'Preferisci una VPN sul router. In alternativa verifica manualmente Wake-on-WAN sul modello esatto e poi abilita solo una configurazione esplicitamente verificata.'
            }
        }

        if ($cgnatKnown -and $cgnat) {
            return [PSCustomObject]@{
                Method = 'ROUTER_RELAY_REQUIRED'
                Label = 'VPN/router con relay'
                Score = 70
                RemoteState = 'SETUP_REQUIRED'
                Reason = 'CGNAT rilevato: un semplice inoltro UDP dall Internet pubblico non e affidabile/disponibile.'
                Action = 'Usa una funzione remota del router, una VPN/relay supportata dal router o un piccolo dispositivo sempre acceso nella rete.'
            }
        }

        return [PSCustomObject]@{
            Method = 'LAN_WOL'
            Label = 'Wake-on-LAN Ethernet'
            Score = 60
            RemoteState = 'LOCAL_ONLY'
            Reason = 'Wake-on-LAN Ethernet disponibile. La rete Internet non e ancora verificata per un accensione da fuori casa/ufficio.'
            Action = 'ACCENDI funziona nella stessa LAN. Per l uso da lontano configura la VPN del router quando disponibile.'
        }
    }

    if ($Amt -and [bool](Get-VargaObjectValue $Amt 'HardwareCandidate' $false)) {
        return [PSCustomObject]@{
            Method = 'INTEL_AMT_CANDIDATE'
            Label = 'Intel AMT/vPro da verificare'
            Score = 55
            RemoteState = 'SETUP_REQUIRED'
            Reason = 'Componenti Intel Management Engine rilevati, ma non e possibile dichiarare AMT remoto pronto senza provisioning esplicito.'
            Action = 'Verifica nel BIOS/UEFI se il PC supporta Intel vPro/AMT e provisiona AMT soltanto se realmente disponibile.'
        }
    }

    return [PSCustomObject]@{
        Method = 'UNAVAILABLE'
        Label = 'Da configurare'
        Score = 0
        RemoteState = 'NOT_READY'
        Reason = 'Non ho trovato ancora un metodo di accensione affidabile.'
        Action = 'Collega il PC via Ethernet e abilita Wake-on-LAN/Magic Packet nel BIOS/UEFI e nella scheda di rete.'
    }
}

function Get-VargaLocalSmartWakeProfile {
    param([string]$DatabasePath, [switch]$Optimize)
    if (-not (Get-Command Get-VargaNetworkProfile -ErrorAction SilentlyContinue)) { throw 'PowerTools.ps1 non caricato.' }

    if ($Optimize) { $optimization = Enable-VargaEthernetWake }
    else { $optimization = [PSCustomObject]@{ Changed = $false; Message = 'Solo diagnosi.' } }

    $network = Get-VargaNetworkProfile
    if (-not $network) { throw 'Rete non rilevata.' }
    $wake = Get-VargaWakeCapability
    $router = Get-VargaSmartRouterInfo -DatabasePath $DatabasePath
    $amt = Get-VargaAmtCapability
    $vpnAdapters = @(Get-VargaVpnAdapters)
    $fastStartup = Get-VargaFastStartupState
    $hibernate = Get-VargaHibernateState

    $prefixLength = 24
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
        if ($route) {
            $ipRecord = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -eq $network.LocalIp } | Select-Object -First 1
            if ($ipRecord) { $prefixLength = [int]$ipRecord.PrefixLength }
        }
    }
    catch { }

    $activeBroadcast = Get-VargaIPv4Broadcast -Address $network.LocalIp -PrefixLength $prefixLength
    $ethernetAddress = Get-VargaEthernetNetworkInfo
    $ethernetBroadcast = [string](Get-VargaObjectValue $ethernetAddress 'Broadcast' '')
    if (-not $ethernetBroadcast) { $ethernetBroadcast = $activeBroadcast }
    $recommendation = Get-VargaSmartWakeRecommendation -Wake $wake -Router $router -Amt $amt

    [PSCustomObject]@{
        Schema = 2
        GeneratedAt = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        Network = [PSCustomObject]@{
            LocalIp = $network.LocalIp
            PrefixLength = $prefixLength
            Broadcast = $activeBroadcast
            Gateway = $network.Gateway
            ActiveAdapter = $network.ActiveAdapter
            ActiveMac = $network.ActiveMac
            EthernetName = $network.EthernetName
            EthernetMac = $network.EthernetMac
            EthernetIp = [string](Get-VargaObjectValue $ethernetAddress 'Ip' '')
            EthernetPrefixLength = [int](Get-VargaObjectValue $ethernetAddress 'PrefixLength' 0)
            EthernetBroadcast = $ethernetBroadcast
            EthernetGateway = [string](Get-VargaObjectValue $ethernetAddress 'Gateway' '')
        }
        Wake = $wake
        Router = $router
        Amt = $amt
        VpnAdapters = $vpnAdapters
        FastStartup = $fastStartup
        Hibernate = $hibernate
        Optimization = $optimization
        Recommendation = $recommendation
    }
}

function Save-VargaLocalSmartWakeProfile {
    param([Parameter(Mandatory)]$Profile, [string]$Path)
    if (-not $Path) {
        $dir = Join-Path $env:APPDATA 'VargaRemote'
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        $Path = Join-Path $dir 'local-smart-wake.json'
    }
    else {
        $parent = Split-Path -Parent $Path
        if ($parent) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
    }
    $Profile | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding UTF8
    return $Path
}

function Get-VargaSmartWakeSummary {
    param([Parameter(Mandatory)]$Profile)
    $network = Get-VargaObjectValue $Profile 'Network' $null
    $wake = Get-VargaObjectValue $Profile 'Wake' $null
    $router = Get-VargaObjectValue $Profile 'Router' $null
    $recommendation = Get-VargaObjectValue $Profile 'Recommendation' $null
    $fastStartup = Get-VargaObjectValue $Profile 'FastStartup' $null
    $optimization = Get-VargaObjectValue $Profile 'Optimization' $null
    $amt = Get-VargaObjectValue $Profile 'Amt' $null

    $label = [string](Get-VargaObjectValue $recommendation 'Label' 'Da configurare')
    $remoteState = [string](Get-VargaObjectValue $recommendation 'RemoteState' 'NOT_READY')
    $reason = [string](Get-VargaObjectValue $recommendation 'Reason' '')
    $action = [string](Get-VargaObjectValue $recommendation 'Action' '')
    $cgnatKnown = [bool](Get-VargaObjectValue $router 'CgnatKnown' $false)
    $cgnat = [bool](Get-VargaObjectValue $router 'Cgnat' $false)
    $cgnatText = if ($cgnatKnown) { if ($cgnat) { 'SI' } else { 'NO' } } else { 'non determinato' }
    $vpnText = if (@(Get-VargaObjectValue $Profile 'VpnAdapters' @()).Count -gt 0) { @(Get-VargaObjectValue $Profile 'VpnAdapters' @()) -join ', ' } else { 'nessuna VPN client attiva sul PC' }
    $armedText = if ([bool](Get-VargaObjectValue $wake 'WakeArmed' $false)) { 'SI' } else { 'NO / non rilevato' }
    $fastKnown = [bool](Get-VargaObjectValue $fastStartup 'Known' $false)
    $fastText = if ($fastKnown) { if ([bool](Get-VargaObjectValue $fastStartup 'Enabled' $false)) { 'attivo' } else { 'disattivo' } } else { 'non rilevato' }
    $amtText = if ([bool](Get-VargaObjectValue $amt 'HardwareCandidate' $false)) { 'candidato rilevato, non provisionato' } else { 'non rilevato' }

    return @(
        "Metodo consigliato: $label",
        "Stato remoto: $remoteState",
        '',
        "Ethernet: $([string](Get-VargaObjectValue $network 'EthernetName' ''))",
        "MAC Ethernet: $([string](Get-VargaObjectValue $network 'EthernetMac' ''))",
        "IP locale attivo: $([string](Get-VargaObjectValue $network 'LocalIp' ''))",
        "IP Ethernet: $([string](Get-VargaObjectValue $network 'EthernetIp' ''))",
        "Broadcast Ethernet: $([string](Get-VargaObjectValue $network 'EthernetBroadcast' (Get-VargaObjectValue $network 'Broadcast' '')))",
        "Wake on Magic Packet: $([string](Get-VargaObjectValue $wake 'WakeOnMagicPacket' 'Unknown'))",
        "Dispositivo armato per wake: $armedText",
        "Gateway: $([string](Get-VargaObjectValue $network 'Gateway' ''))",
        "MAC gateway: $([string](Get-VargaObjectValue $router 'GatewayMac' ''))",
        "Router: $([string](Get-VargaObjectValue $router 'Name' ''))",
        "IP WAN router: $([string](Get-VargaObjectValue $router 'WanIp' ''))",
        "IP pubblico visto da Internet: $([string](Get-VargaObjectValue $router 'PublicIp' ''))",
        "CGNAT: $cgnatText",
        "VPN client locali: $vpnText",
        "Intel AMT/vPro: $amtText",
        "Avvio rapido Windows: $fastText",
        '',
        $reason,
        $(if ($action) { "Azione: $action" } else { '' }),
        '',
        "Ottimizzazione: $([string](Get-VargaObjectValue $optimization 'Message' ''))"
    ) -join "`r`n"
}

function ConvertTo-VargaPairingCode {
    param([Parameter(Mandatory)]$Payload)
    $json = $Payload | ConvertTo-Json -Depth 12 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    return 'VR1:' + [Convert]::ToBase64String($bytes)
}

function ConvertFrom-VargaPairingCode {
    param([Parameter(Mandatory)][string]$Code)
    $text = $Code.Trim()
    if (-not $text.StartsWith('VR1:', [StringComparison]::OrdinalIgnoreCase)) { throw 'Codice Varga Remote non riconosciuto.' }
    try {
        $bytes = [Convert]::FromBase64String($text.Substring(4))
        $json = [Text.Encoding]::UTF8.GetString($bytes)
        $payload = $json | ConvertFrom-Json
        if ([string](Get-VargaObjectValue $payload 'app' '') -ne 'VargaRemote') { throw 'Profilo non valido.' }
        return $payload
    }
    catch { throw 'Profilo Varga Remote non valido o danneggiato.' }
}

function Get-VargaLocalPairingCode {
    param([Parameter(Mandatory)][string]$RustDeskId, [string]$DatabasePath, [switch]$Optimize)
    $profile = Get-VargaLocalSmartWakeProfile -DatabasePath $DatabasePath -Optimize:$Optimize
    Save-VargaLocalSmartWakeProfile -Profile $profile | Out-Null
    $label = $env:COMPUTERNAME
    try {
        $installJson = Join-Path $PSScriptRoot 'install.json'
        if (Test-Path $installJson) {
            $install = Get-Content $installJson -Raw | ConvertFrom-Json
            $installedName = [string](Get-VargaObjectValue $install 'computerName' '')
            if ($installedName) { $label = $installedName }
        }
    }
    catch { }

    $payload = [PSCustomObject]@{
        app = 'VargaRemote'
        schema = 2
        name = $label
        id = $RustDeskId
        host = $env:COMPUTERNAME
        mac = [string](Get-VargaObjectValue (Get-VargaObjectValue $profile 'Network' $null) 'EthernetMac' '')
        smartWake = $profile
    }
    return ConvertTo-VargaPairingCode -Payload $payload
}

function Get-VargaDeviceSmartWakeLabel {
    param($Device)
    $smart = Get-VargaObjectValue $Device 'smartWake' $null
    if ($smart) {
        $recommendation = Get-VargaObjectValue $smart 'Recommendation' $null
        if ($recommendation) {
            $label = [string](Get-VargaObjectValue $recommendation 'Label' '')
            $state = [string](Get-VargaObjectValue $recommendation 'RemoteState' '')
            if ($state -eq 'SETUP_REQUIRED') { return "$label (setup)" }
            if ($state -eq 'LOCAL_ONLY') { return "$label (LAN)" }
            if ($label) { return $label }
        }
    }
    return 'Auto / LAN'
}

function Get-VargaWakeMacFromDevice {
    param($Device)
    $mac = [string](Get-VargaObjectValue $Device 'mac' '')
    if ($mac) { return $mac }
    $smart = Get-VargaObjectValue $Device 'smartWake' $null
    $network = Get-VargaObjectValue $smart 'Network' $null
    return [string](Get-VargaObjectValue $network 'EthernetMac' '')
}

function Test-VargaSameLanAsTarget {
    param($TargetRouter, $CurrentNetwork)
    if (-not $TargetRouter -or -not $CurrentNetwork) { return $false }
    $targetGateway = [string](Get-VargaObjectValue $TargetRouter 'Gateway' '')
    $targetGatewayMac = ([string](Get-VargaObjectValue $TargetRouter 'GatewayMac' '')).ToUpperInvariant()
    if (-not $targetGateway -or -not $targetGatewayMac) { return $false }
    if ([string]$CurrentNetwork.Gateway -ne $targetGateway) { return $false }
    $currentGatewayMac = (Get-VargaGatewayMac -Gateway ([string]$CurrentNetwork.Gateway)).ToUpperInvariant()
    if (-not $currentGatewayMac) { return $false }
    return ($currentGatewayMac -eq $targetGatewayMac)
}

function Invoke-VargaSmartWake {
    param([Parameter(Mandatory)]$Device)
    if (-not (Get-Command Send-VargaWakeOnLan -ErrorAction SilentlyContinue)) { throw 'PowerTools.ps1 non caricato.' }

    $mac = Get-VargaWakeMacFromDevice -Device $Device
    if (-not $mac) { throw 'MAC Ethernet mancante. Importa il profilo Varga Remote del PC.' }

    $smart = Get-VargaObjectValue $Device 'smartWake' $null
    if (-not $smart) {
        Send-VargaWakeOnLan -MacAddress $mac -Broadcast '255.255.255.255' -Port 9
        return [PSCustomObject]@{
            Sent = $true
            Ready = $true
            Method = 'LEGACY_LAN_WOL'
            Label = 'Wake-on-LAN locale (profilo precedente)'
            Remote = $false
            Destination = '255.255.255.255'
            Message = 'Il PC non ha ancora un profilo Smart Wake. Ho mantenuto la compatibilita con la 0.3 inviando il Magic Packet soltanto nella LAN corrente. Usa COPIA PROFILO sul PC remoto per abilitare la diagnostica automatica.'
        }
    }
    $targetNetwork = Get-VargaObjectValue $smart 'Network' $null
    $targetRouter = Get-VargaObjectValue $smart 'Router' $null
    $recommendation = Get-VargaObjectValue $smart 'Recommendation' $null
    $targetIp = [string](Get-VargaObjectValue $targetNetwork 'EthernetIp' '')
    if (-not $targetIp) { $targetIp = [string](Get-VargaObjectValue $targetNetwork 'LocalIp' '') }
    $targetBroadcast = [string](Get-VargaObjectValue $targetNetwork 'EthernetBroadcast' '')
    if (-not $targetBroadcast) { $targetBroadcast = [string](Get-VargaObjectValue $targetNetwork 'Broadcast' '') }
    $publicIp = [string](Get-VargaObjectValue $targetRouter 'PublicIp' '')
    $wakeOnWanVerified = [bool](Get-VargaObjectValue $targetRouter 'WakeOnWanVerified' $false)
    $current = Get-VargaNetworkProfile

    # Strong same-LAN check: gateway address + gateway MAC. This avoids treating two
    # unrelated sites that both use 192.168.1.1 as the same network.
    if (Test-VargaSameLanAsTarget -TargetRouter $targetRouter -CurrentNetwork $current) {
        if (-not $targetBroadcast) { $targetBroadcast = '255.255.255.255' }
        Send-VargaWakeOnLan -MacAddress $mac -Broadcast $targetBroadcast -Port 9
        Send-VargaWakeOnLan -MacAddress $mac -Broadcast '255.255.255.255' -Port 7
        return [PSCustomObject]@{
            Sent = $true
            Ready = $true
            Method = 'LAN_WOL'
            Label = 'Wake-on-LAN Ethernet'
            Remote = $false
            Destination = $targetBroadcast
            Message = 'Stessa rete verificata tramite MAC del gateway. Magic Packet inviato alla scheda Ethernet del PC selezionato.'
        }
    }

    # A VPN is considered usable only when Windows actually routes the target LAN
    # through a VPN adapter; merely having a VPN client installed is not enough.
    $route = Get-VargaRouteToTarget -TargetAddress $targetIp
    if ($route -and $route.IsVpn) {
        $destinations = @()
        if ($targetIp) { $destinations += $targetIp }
        if ($targetBroadcast) { $destinations += $targetBroadcast }
        $destinations = @($destinations | Select-Object -Unique)
        foreach ($destination in $destinations) {
            Send-VargaWakeOnLan -MacAddress $mac -Broadcast $destination -Port 9
            Send-VargaWakeOnLan -MacAddress $mac -Broadcast $destination -Port 7
        }
        return [PSCustomObject]@{
            Sent = $true
            Ready = $true
            Method = 'VPN_WOL'
            Label = 'VPN + Wake-on-LAN'
            Remote = $true
            Destination = if ($targetBroadcast) { $targetBroadcast } else { $targetIp }
            Message = "Rotta VPN verificata su $($route.InterfaceName). Varga Remote ha inviato il Magic Packet via rete remota."
        }
    }

    # Direct WAN is never auto-enabled. It is used only when a future/manual
    # verification explicitly marks the target profile as verified.
    if ($wakeOnWanVerified -and $publicIp) {
        Send-VargaWakeOnLan -MacAddress $mac -Broadcast $publicIp -Port 9
        Send-VargaWakeOnLan -MacAddress $mac -Broadcast $publicIp -Port 7
        return [PSCustomObject]@{
            Sent = $true
            Ready = $true
            Method = 'WAKE_ON_WAN_VERIFIED'
            Label = 'Wake-on-WAN verificato'
            Remote = $true
            Destination = $publicIp
            Message = 'Profilo Wake-on-WAN precedentemente verificato: pacchetto inviato all IP pubblico configurato.'
        }
    }

    $label = [string](Get-VargaObjectValue $recommendation 'Label' 'Smart Wake da configurare')
    $reason = [string](Get-VargaObjectValue $recommendation 'Reason' 'Non e disponibile una rotta remota verificata.')
    $action = [string](Get-VargaObjectValue $recommendation 'Action' 'Apri SMART WAKE per la diagnostica.')
    if ($route -and (-not $route.IsVpn) -and $targetIp) {
        $reason += " La rotta verso $targetIp passa da $($route.InterfaceName), non da una VPN: potrebbe esserci una sovrapposizione tra la rete locale corrente e la rete del PC remoto."
    }
    return [PSCustomObject]@{
        Sent = $false
        Ready = $false
        Method = [string](Get-VargaObjectValue $recommendation 'Method' 'NOT_READY')
        Label = $label
        Remote = $true
        Destination = ''
        Message = "$reason`r`n`r`n$action"
    }
}
