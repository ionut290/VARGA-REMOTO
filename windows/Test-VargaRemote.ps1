#requires -Version 5.1
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Common.ps1')
$powerToolsPath = Join-Path $PSScriptRoot 'PowerTools.ps1'
if (Test-Path $powerToolsPath) { . $powerToolsPath }
$smartWakePath = Join-Path $PSScriptRoot 'SmartWake.ps1'
if (Test-Path $smartWakePath) { . $smartWakePath }

Write-Host 'VARGA REMOTE - VERIFICA INSTALLAZIONE 0.4 SMART WAKE' -ForegroundColor Cyan

$rustDesk = Get-VargaRemoteRustDeskPath
if ($rustDesk) {
    Write-Host "[OK] RustDesk: $rustDesk" -ForegroundColor Green
}
else {
    Write-Host '[ERRORE] RustDesk non trovato.' -ForegroundColor Red
    exit 1
}

$services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like '*RustDesk*' -or $_.DisplayName -like '*RustDesk*'
})
if ($services.Count -gt 0) {
    foreach ($service in $services) {
        $startMode = (Get-CimInstance Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue).StartMode
        Write-Host "[OK] Servizio $($service.Name): $($service.Status), avvio $startMode" -ForegroundColor Green
    }
}
else {
    Write-Host '[ERRORE] Servizio automatico RustDesk non trovato.' -ForegroundColor Red
}

$id = (& $rustDesk --get-id 2>$null | Out-String).Trim()
if ($id) {
    Write-Host "[OK] ID del PC: $id" -ForegroundColor Green
}
else {
    Write-Host '[ATTENZIONE] ID non ancora disponibile. Controlla rete e server.' -ForegroundColor Yellow
}

Write-Host
Write-Host 'SMART WAKE - DIAGNOSTICA AUTOMATICA' -ForegroundColor Cyan
if (Get-Command Get-VargaLocalSmartWakeProfile -ErrorAction SilentlyContinue) {
    try {
        $profile = Get-VargaLocalSmartWakeProfile -DatabasePath (Join-Path $PSScriptRoot 'router-database.json')
        $recommendation = Get-VargaObjectValue $profile 'Recommendation' $null
        $state = [string](Get-VargaObjectValue $recommendation 'RemoteState' 'NOT_READY')
        $color = if ($state -eq 'LOCAL_ONLY') { 'Yellow' } elseif ($state -eq 'SETUP_REQUIRED') { 'Yellow' } elseif ($state -eq 'NOT_READY') { 'Red' } else { 'Green' }
        Write-Host (Get-VargaSmartWakeSummary -Profile $profile) -ForegroundColor $color
    }
    catch {
        Write-Host "[ATTENZIONE] Smart Wake: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
else {
    Write-Host '[ATTENZIONE] SmartWake.ps1 non disponibile.' -ForegroundColor Yellow
}

Write-Host
Write-Host 'Controlli manuali:' -ForegroundColor Yellow
Write-Host '- collega il PC controllato via Ethernet per Wake-on-LAN;'
Write-Host '- nel BIOS/UEFI abilita Wake-on-LAN / Power On by PCI-E se il test lo richiede;'
Write-Host '- per accendere da Internet usa preferibilmente la VPN del router;'
Write-Host '- Varga Remote non apre automaticamente porte UDP sul router;'
Write-Host '- il PC controllato vede la notifica durante la connessione;'
Write-Host '- modalita privacy disabilitata e blocco input locale disabilitato;'
Write-Host '- dopo un riavvio il servizio RustDesk resta Running/Automatic.'
