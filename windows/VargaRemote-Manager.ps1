#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'Common.ps1')
$powerToolsPath = Join-Path $PSScriptRoot 'PowerTools.ps1'
if (Test-Path $powerToolsPath) { . $powerToolsPath }
$smartWakePath = Join-Path $PSScriptRoot 'SmartWake.ps1'
if (Test-Path $smartWakePath) { . $smartWakePath }
$externalAccessPath = Join-Path $PSScriptRoot 'ExternalAccess.ps1'
if (Test-Path $externalAccessPath) { . $externalAccessPath }

[Windows.Forms.Application]::EnableVisualStyles()
$dataDir = Join-Path $env:APPDATA 'VargaRemote'
$dataFile = Join-Path $dataDir 'devices.json'
New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
$databasePath = Join-Path $PSScriptRoot 'router-database.json'
$manifestPath = Join-Path $PSScriptRoot 'version.json'
$updateScriptPath = Join-Path $PSScriptRoot 'Update-VargaRemote.ps1'
$displayVersion = '0.8.1-beta'
if (Test-Path $manifestPath) {
    try { $displayVersion = [string](Get-Content $manifestPath -Raw | ConvertFrom-Json).version }
    catch { }
}

function Load-Devices {
    if (-not (Test-Path $dataFile)) { return @() }
    try { return @((Get-Content $dataFile -Raw | ConvertFrom-Json)) }
    catch { return @() }
}

function Save-Devices([array]$items) {
    @($items) | ConvertTo-Json -Depth 12 | Set-Content $dataFile -Encoding UTF8
}

function Get-DeviceValue($device, [string]$propertyName) {
    $property = $device.PSObject.Properties[$propertyName]
    if ($property) { return [string]$property.Value }
    return ''
}

function Get-DeviceObjectValue($device, [string]$propertyName) {
    $property = $device.PSObject.Properties[$propertyName]
    if ($property) { return $property.Value }
    return $null
}

$script:devices = @(Load-Devices)
$rustDeskPath = Get-VargaRemoteRustDeskPath
$localId = $null
if ($rustDeskPath) {
    $localIdOutput = (& $rustDeskPath --get-id 2>$null | Out-String).Trim()
    if ($localIdOutput -match '(?m)^\s*([A-Za-z][A-Za-z0-9-]{5,}|[0-9]{6,})\s*$') {
        $localId = $matches[1]
    }
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Varga Remote Manager - Smart Wake'
$form.Size = New-Object Drawing.Size(920, 750)
$form.MinimumSize = New-Object Drawing.Size(920, 750)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::FromArgb(15, 23, 42)
$form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

$title = New-Object Windows.Forms.Label
$title.Text = 'Varga Remote'
$title.Font = New-Object Drawing.Font('Segoe UI Semibold', 22)
$title.ForeColor = [Drawing.Color]::FromArgb(45, 212, 191)
$title.Location = New-Object Drawing.Point(24, 18)
$title.AutoSize = $true
$form.Controls.Add($title)

$versionLabel = New-Object Windows.Forms.Label
$versionLabel.Text = "SMART WAKE $displayVersion"
$versionLabel.ForeColor = [Drawing.Color]::FromArgb(94, 234, 212)
$versionLabel.Location = New-Object Drawing.Point(235, 34)
$versionLabel.AutoSize = $true
$form.Controls.Add($versionLabel)

$updateButton = New-Object Windows.Forms.Button
$updateButton.Text = 'AGGIORNA'
$updateButton.Size = New-Object Drawing.Size(110, 32)
$updateButton.Location = New-Object Drawing.Point(774, 26)
$updateButton.Anchor = 'Top,Right'
$updateButton.FlatStyle = 'Flat'
$updateButton.FlatAppearance.BorderSize = 0
$updateButton.BackColor = [Drawing.Color]::FromArgb(30, 64, 175)
$updateButton.ForeColor = [Drawing.Color]::White
$form.Controls.Add($updateButton)

$subtitle = New-Object Windows.Forms.Label
$subtitle.Text = 'PC autorizzati - credenziali permanenti protette su questo PC'
$subtitle.ForeColor = [Drawing.Color]::FromArgb(148, 163, 184)
$subtitle.Location = New-Object Drawing.Point(28, 60)
$subtitle.AutoSize = $true
$form.Controls.Add($subtitle)

$localIdLabel = New-Object Windows.Forms.Label
$localIdLabel.Text = if ($localId) { "ID di questo PC: $localId" } else { 'ID di questo PC: non disponibile' }
$localIdLabel.ForeColor = [Drawing.Color]::FromArgb(251, 191, 36)
$localIdLabel.Location = New-Object Drawing.Point(28, 82)
$localIdLabel.AutoSize = $true
$form.Controls.Add($localIdLabel)

$list = New-Object Windows.Forms.ListView
$list.Location = New-Object Drawing.Point(28, 112)
$list.Size = New-Object Drawing.Size(856, 330)
$list.Anchor = 'Top,Bottom,Left,Right'
$list.View = 'Details'
$list.FullRowSelect = $true
$list.GridLines = $false
$list.BackColor = [Drawing.Color]::FromArgb(30, 41, 59)
$list.ForeColor = [Drawing.Color]::White
[void]$list.Columns.Add('Nome', 150)
[void]$list.Columns.Add('ID RustDesk', 130)
[void]$list.Columns.Add('IP / Nome rete', 140)
[void]$list.Columns.Add('MAC Ethernet', 150)
[void]$list.Columns.Add('Smart Wake', 170)
[void]$list.Columns.Add('Accesso', 115)
$form.Controls.Add($list)

function Refresh-List {
    $list.Items.Clear()
    foreach ($device in $script:devices) {
        $item = New-Object Windows.Forms.ListViewItem((Get-DeviceValue $device 'name'))
        [void]$item.SubItems.Add((Get-DeviceValue $device 'id'))
        [void]$item.SubItems.Add((Get-DeviceValue $device 'host'))
        [void]$item.SubItems.Add((Get-DeviceValue $device 'mac'))
        $wakeLabel = if (Get-Command Get-VargaDeviceSmartWakeLabel -ErrorAction SilentlyContinue) {
            Get-VargaDeviceSmartWakeLabel -Device $device
        } else { 'Auto / LAN' }
        [void]$item.SubItems.Add($wakeLabel)
        [void]$item.SubItems.Add('Permanente')
        $item.Tag = $device
        [void]$list.Items.Add($item)
    }
}

function New-ActionButton($text, $x, $y, $color) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $text
    $button.Size = New-Object Drawing.Size(160, 42)
    $button.Location = New-Object Drawing.Point($x, $y)
    $button.Anchor = 'Bottom,Left'
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $color
    $button.ForeColor = [Drawing.Color]::White
    return $button
}

$add = New-ActionButton 'Aggiungi PC' 28 462 ([Drawing.Color]::FromArgb(51, 65, 85))
$connect = New-ActionButton 'Connetti' 200 462 ([Drawing.Color]::FromArgb(13, 148, 136))
$remove = New-ActionButton 'Rimuovi elenco' 372 462 ([Drawing.Color]::FromArgb(153, 27, 27))
$open = New-ActionButton 'Copia ID locale' 544 462 ([Drawing.Color]::FromArgb(51, 65, 85))
$networkButton = New-ActionButton 'SMART WAKE' 716 462 ([Drawing.Color]::FromArgb(30, 64, 175))
$wakeButton = New-ActionButton 'ACCENDI' 28 516 ([Drawing.Color]::FromArgb(21, 128, 61))
$restartButton = New-ActionButton 'RIAVVIA' 200 516 ([Drawing.Color]::FromArgb(180, 83, 9))
$shutdownButton = New-ActionButton 'SPEGNI' 372 516 ([Drawing.Color]::FromArgb(185, 28, 28))
$cancelButton = New-ActionButton 'ANNULLA' 544 516 ([Drawing.Color]::FromArgb(51, 65, 85))
$copyProfileButton = New-ActionButton 'COPIA PROFILO' 716 516 ([Drawing.Color]::FromArgb(6, 95, 70))
$externalButton = New-ActionButton 'CONFIGURA AUTOMATICAMENTE ACCESSO ESTERNO' 28 570 ([Drawing.Color]::FromArgb(88, 28, 135))
$externalButton.Width = 856
$form.Controls.AddRange(@($add, $connect, $remove, $open, $networkButton, $wakeButton, $restartButton, $shutdownButton, $cancelButton, $copyProfileButton, $externalButton))

$statusLabel = New-Object Windows.Forms.Label
$statusLabel.Text = 'Smart Wake sceglie automaticamente il metodo migliore disponibile.'
$statusLabel.ForeColor = [Drawing.Color]::FromArgb(148, 163, 184)
$statusLabel.Location = New-Object Drawing.Point(28, 626)
$statusLabel.Size = New-Object Drawing.Size(850, 34)
$statusLabel.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($statusLabel)

function Get-SelectedDevice {
    if ($list.SelectedItems.Count -ne 1) {
        [Windows.Forms.MessageBox]::Show('Seleziona un PC.', 'Varga Remote') | Out-Null
        return $null
    }
    return $list.SelectedItems[0].Tag
}

$add.Add_Click({
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'Aggiungi PC autorizzato'
    $dialog.Size = New-Object Drawing.Size(470, 500)
    $dialog.StartPosition = 'CenterParent'
    $dialog.Tag = $null

    $pasteProfile = New-Object Windows.Forms.Button
    $pasteProfile.Text = 'INCOLLA PROFILO VARGA'
    $pasteProfile.Location = New-Object Drawing.Point(20, 18)
    $pasteProfile.Size = New-Object Drawing.Size(190, 34)

    $profileStatus = New-Object Windows.Forms.Label
    $profileStatus.Text = 'Oppure compila i campi manualmente.'
    $profileStatus.Location = New-Object Drawing.Point(220, 25)
    $profileStatus.Size = New-Object Drawing.Size(215, 26)
    $profileStatus.ForeColor = [Drawing.Color]::DimGray

    $nameLabel = New-Object Windows.Forms.Label
    $nameLabel.Text = 'Nome del PC'
    $nameLabel.Location = New-Object Drawing.Point(20, 70)
    $nameLabel.AutoSize = $true
    $nameBox = New-Object Windows.Forms.TextBox
    $nameBox.Location = New-Object Drawing.Point(20, 96)
    $nameBox.Width = 410

    $idLabel = New-Object Windows.Forms.Label
    $idLabel.Text = 'ID RustDesk'
    $idLabel.Location = New-Object Drawing.Point(20, 132)
    $idLabel.AutoSize = $true
    $idBox = New-Object Windows.Forms.TextBox
    $idBox.Location = New-Object Drawing.Point(20, 158)
    $idBox.Width = 410

    $hostLabel = New-Object Windows.Forms.Label
    $hostLabel.Text = 'IP o nome Windows del PC (per Spegni/Riavvia)'
    $hostLabel.Location = New-Object Drawing.Point(20, 194)
    $hostLabel.AutoSize = $true
    $hostBox = New-Object Windows.Forms.TextBox
    $hostBox.Location = New-Object Drawing.Point(20, 220)
    $hostBox.Width = 410

    $macLabel = New-Object Windows.Forms.Label
    $macLabel.Text = 'MAC Ethernet (per Accendi)'
    $macLabel.Location = New-Object Drawing.Point(20, 256)
    $macLabel.AutoSize = $true
    $macBox = New-Object Windows.Forms.TextBox
    $macBox.Location = New-Object Drawing.Point(20, 282)
    $macBox.Width = 410

    $hint = New-Object Windows.Forms.Label
    $hint.Text = 'Con il profilo Varga, MAC, rete, router e metodo Smart Wake vengono importati automaticamente.'
    $hint.Location = New-Object Drawing.Point(20, 320)
    $hint.Size = New-Object Drawing.Size(410, 48)
    $hint.ForeColor = [Drawing.Color]::DimGray

    $ok = New-Object Windows.Forms.Button
    $ok.Text = 'Salva'
    $ok.Location = New-Object Drawing.Point(310, 390)
    $ok.Size = New-Object Drawing.Size(120, 36)
    $ok.DialogResult = [Windows.Forms.DialogResult]::OK
    $dialog.AcceptButton = $ok

    $pasteProfile.Add_Click({
        try {
            if (-not [Windows.Forms.Clipboard]::ContainsText()) { throw 'Negli appunti non c e un profilo Varga Remote.' }
            $payload = ConvertFrom-VargaPairingCode -Code ([Windows.Forms.Clipboard]::GetText())
            $nameBox.Text = [string](Get-VargaObjectValue $payload 'name' '')
            $idBox.Text = [string](Get-VargaObjectValue $payload 'id' '')
            $hostBox.Text = [string](Get-VargaObjectValue $payload 'host' '')
            $macBox.Text = [string](Get-VargaObjectValue $payload 'mac' '')
            $dialog.Tag = $payload
            $smart = Get-VargaObjectValue $payload 'smartWake' $null
            $recommendation = Get-VargaObjectValue $smart 'Recommendation' $null
            $label = if ($recommendation) { [string](Get-VargaObjectValue $recommendation 'Label' 'profilo importato') } else { 'profilo importato' }
            $profileStatus.Text = "OK - $label"
            $profileStatus.ForeColor = [Drawing.Color]::DarkGreen
        }
        catch {
            [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Profilo Varga Remote', 'OK', 'Warning') | Out-Null
        }
    })

    $dialog.Controls.AddRange(@($pasteProfile, $profileStatus, $nameLabel, $nameBox, $idLabel, $idBox, $hostLabel, $hostBox, $macLabel, $macBox, $hint, $ok))

    if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
        $safeId = ($idBox.Text -replace '[^A-Za-z0-9-]', '')
        if ($nameBox.Text.Trim() -and $safeId) {
            if ($localId -and $safeId.Equals($localId, [StringComparison]::OrdinalIgnoreCase)) {
                [Windows.Forms.MessageBox]::Show(
                    'Questo e ID del PC che stai usando. Inserisci ID dell altro computer.',
                    'Collegamento al proprio PC bloccato', 'OK', 'Warning') | Out-Null
                return
            }
            if (@($script:devices | Where-Object { [string]$_.id -eq $safeId }).Count -gt 0) {
                [Windows.Forms.MessageBox]::Show('Questo ID e gia presente.', 'Varga Remote') | Out-Null
                return
            }
            $safeHost = ($hostBox.Text.Trim() -replace '[^A-Za-z0-9._-]', '')
            $safeMac = ($macBox.Text.Trim() -replace '[^A-Fa-f0-9:-]', '').ToUpperInvariant()
            $importedPayload = $dialog.Tag
            $smartWake = if ($importedPayload) { Get-VargaObjectValue $importedPayload 'smartWake' $null } else { $null }
            $script:devices += [PSCustomObject]@{
                name = $nameBox.Text.Trim()
                id = $safeId
                host = $safeHost
                mac = $safeMac
                smartWake = $smartWake
                addedAt = (Get-Date).ToString('o')
            }
            Save-Devices $script:devices
            Refresh-List
        }
    }
})

$connect.Add_Click({
    if ($list.SelectedItems.Count -ne 1) {
        [Windows.Forms.MessageBox]::Show('Seleziona un PC.', 'Varga Remote') | Out-Null
        return
    }
    $rustDesk = Get-VargaRemoteRustDeskPath
    if (-not $rustDesk) {
        [Windows.Forms.MessageBox]::Show('Installa prima RustDesk sul PC di controllo.', 'Varga Remote') | Out-Null
        return
    }
    $id = [string]$list.SelectedItems[0].Tag.id
    if ($localId -and $id.Equals($localId, [StringComparison]::OrdinalIgnoreCase)) {
        [Windows.Forms.MessageBox]::Show(
            'Hai selezionato questo stesso PC. Aggiungi ID mostrato sull altro computer.',
            'Collegamento bloccato', 'OK', 'Warning') | Out-Null
        return
    }
    if (Get-Command Get-VargaExternalAccessConfig -ErrorAction SilentlyContinue) {
        $savedAccess = Get-VargaExternalAccessConfig -DeviceId $id
        $protectedPassword = if ($savedAccess) { [string](Get-VargaObjectValue $savedAccess 'protectedRustDeskPassword' '') } else { '' }
        if ($protectedPassword) {
            try {
                $permanentPassword = Unprotect-VargaExternalToken -ProtectedToken $protectedPassword
                [Windows.Forms.Clipboard]::SetText($permanentPassword)
                $statusLabel.Text = 'Password permanente copiata. Se RustDesk la richiede, incollala e scegli Ricorda.'
            }
            catch { }
        }
    }
    Start-Process -FilePath $rustDesk -ArgumentList @('--connect', $id)
})

$remove.Add_Click({
    if ($list.SelectedItems.Count -ne 1) { return }
    $answer = [Windows.Forms.MessageBox]::Show(
        'Rimuovere questo PC dal pannello? Questa azione non revoca la password sul PC controllato.',
        'Varga Remote', 'YesNo', 'Warning')
    if ($answer -eq 'Yes') {
        $selectedId = [string]$list.SelectedItems[0].Tag.id
        $script:devices = @($script:devices | Where-Object { [string]$_.id -ne $selectedId })
        Save-Devices $script:devices
        Refresh-List
    }
})

$open.Add_Click({
    if ($localId) {
        [Windows.Forms.Clipboard]::SetText($localId)
        [Windows.Forms.MessageBox]::Show("ID locale copiato: $localId", 'Varga Remote') | Out-Null
    }
    else {
        [Windows.Forms.MessageBox]::Show('ID locale non disponibile.', 'Varga Remote') | Out-Null
    }
})

$copyProfileButton.Add_Click({
    if (-not $localId) {
        [Windows.Forms.MessageBox]::Show('ID locale non disponibile.', 'Profilo Varga Remote') | Out-Null
        return
    }
    if (-not (Get-Command Get-VargaLocalPairingCode -ErrorAction SilentlyContinue)) {
        [Windows.Forms.MessageBox]::Show('Modulo Smart Wake non disponibile.', 'Profilo Varga Remote') | Out-Null
        return
    }
    try {
        $form.UseWaitCursor = $true
        $statusLabel.Text = 'Analisi Ethernet, router e accesso remoto in corso...'
        [Windows.Forms.Application]::DoEvents()
        $code = Get-VargaLocalPairingCode -RustDeskId $localId -DatabasePath $databasePath -Optimize
        [Windows.Forms.Clipboard]::SetText($code)
        $statusLabel.Text = 'Profilo Smart Wake copiato negli appunti.'
        [Windows.Forms.MessageBox]::Show(
            "Profilo copiato.`r`n`r`nSul secondo PC apri Varga Remote > Aggiungi PC > INCOLLA PROFILO VARGA.`r`n`r`nNon contiene la password RustDesk.",
            'Profilo Varga Remote', 'OK', 'Information') | Out-Null
    }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Profilo Varga Remote', 'OK', 'Error') | Out-Null }
    finally { $form.UseWaitCursor = $false }
})

$networkButton.Add_Click({
    try {
        $form.UseWaitCursor = $true
        $statusLabel.Text = 'Smart Wake sta cercando automaticamente la soluzione migliore...'
        [Windows.Forms.Application]::DoEvents()

        $profile = $null
        $targetName = 'questo PC'
        if ($list.SelectedItems.Count -eq 1) {
            $selected = $list.SelectedItems[0].Tag
            $profile = Get-DeviceObjectValue $selected 'smartWake'
            if ($profile) { $targetName = Get-DeviceValue $selected 'name' }
        }
        if (-not $profile) {
            $profile = Get-VargaLocalSmartWakeProfile -DatabasePath $databasePath -Optimize
            Save-VargaLocalSmartWakeProfile -Profile $profile | Out-Null
        }
        $summary = Get-VargaSmartWakeSummary -Profile $profile
        $recommendation = Get-VargaObjectValue $profile 'Recommendation' $null
        $recommendationLabel = [string](Get-VargaObjectValue $recommendation 'Label' 'Da configurare')
        $statusLabel.Text = "Smart Wake: $recommendationLabel"
        [Windows.Forms.MessageBox]::Show(
            "Analisi per: $targetName`r`n`r`n$summary",
            'Smart Wake - diagnostica automatica', 'OK', 'Information') | Out-Null
    }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Smart Wake', 'OK', 'Error') | Out-Null }
    finally { $form.UseWaitCursor = $false }
})

$wakeButton.Add_Click({
    $device = Get-SelectedDevice
    if (-not $device) { return }
    try {
        $externalConfig = $null
        if (Get-Command Get-VargaExternalAccessConfig -ErrorAction SilentlyContinue) {
            $externalConfig = Get-VargaExternalAccessConfig -DeviceId (Get-DeviceValue $device 'id')
        }
        if ($externalConfig -and [string]$externalConfig.relayUrl) {
            $mac = Get-DeviceValue $device 'mac'
            if (-not $mac) { throw 'MAC Ethernet mancante.' }
            $result = Invoke-VargaExternalWake -Config $externalConfig -MacAddress $mac
            $statusLabel.Text = 'ACCENDI: comando inviato tramite Varga Relay e Tailscale.'
            [Windows.Forms.MessageBox]::Show(
                'Comando di accensione inviato al Varga Relay nella rete del PC.',
                'ACCENDI DA INTERNET', 'OK', 'Information') | Out-Null
            return
        }
        if (Get-Command Invoke-VargaSmartWake -ErrorAction SilentlyContinue) {
            $result = Invoke-VargaSmartWake -Device $device
            if ($result.Sent) {
                $statusLabel.Text = "ACCENDI: $($result.Label) -> $($result.Destination)"
                [Windows.Forms.MessageBox]::Show(
                    "Metodo scelto automaticamente: $($result.Label)`r`nDestinazione: $($result.Destination)`r`n`r`n$($result.Message)",
                    'ACCENDI - Smart Wake', 'OK', 'Information') | Out-Null
            }
            else {
                $statusLabel.Text = "ACCENDI: configurazione remota richiesta - $($result.Label)"
                [Windows.Forms.MessageBox]::Show(
                    "Smart Wake ha rilevato la soluzione migliore, ma non esiste ancora una rotta remota verificata.`r`n`r`nSoluzione: $($result.Label)`r`n`r`n$($result.Message)",
                    'ACCENDI - configurazione richiesta', 'OK', 'Warning') | Out-Null
            }
        }
        else {
            $mac = Get-DeviceValue $device 'mac'
            if (-not $mac) { throw 'MAC Ethernet mancante.' }
            Send-VargaWakeOnLan -MacAddress $mac
            [Windows.Forms.MessageBox]::Show('Pacchetto Wake-on-LAN inviato.', 'ACCENDI') | Out-Null
        }
    }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'ACCENDI', 'OK', 'Error') | Out-Null }
})

function Invoke-PowerButton([string]$action, [string]$label) {
    $device = Get-SelectedDevice
    if (-not $device) { return }
    if ($action -ne 'cancel') {
        $answer = [Windows.Forms.MessageBox]::Show(
            "$label il PC $((Get-DeviceValue $device 'name'))? Il comando partira tra 60 secondi.",
            'Conferma alimentazione', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
    }
    try {
        $externalConfig = $null
        if (Get-Command Get-VargaExternalAccessConfig -ErrorAction SilentlyContinue) {
            $externalConfig = Get-VargaExternalAccessConfig -DeviceId (Get-DeviceValue $device 'id')
        }
        if ($externalConfig -and [string]$externalConfig.powerUrl) {
            Invoke-VargaExternalPower -Config $externalConfig -Action $action -DelaySeconds 60 | Out-Null
            [Windows.Forms.MessageBox]::Show("Comando $label inviato tramite Tailscale.", 'Varga Remote') | Out-Null
            return
        }
        $hostName = Get-DeviceValue $device 'host'
        if (-not $hostName) { throw 'Configura ACCESSO ESTERNO oppure indica IP/nome Windows del PC.' }
        Invoke-VargaWindowsPower -Action $action -Computer $hostName -DelaySeconds 60
        [Windows.Forms.MessageBox]::Show("Comando $label inviato.", 'Varga Remote') | Out-Null
    }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, $label, 'OK', 'Error') | Out-Null }
}

$shutdownButton.Add_Click({ Invoke-PowerButton 'shutdown' 'SPEGNI' })
$restartButton.Add_Click({ Invoke-PowerButton 'restart' 'RIAVVIA' })
$cancelButton.Add_Click({ Invoke-PowerButton 'cancel' 'ANNULLA' })

$externalButton.Add_Click({
    if (-not (Get-Command Save-VargaExternalAccessConfig -ErrorAction SilentlyContinue)) {
        [Windows.Forms.MessageBox]::Show('Modulo Accesso Esterno non disponibile.', 'Varga Remote', 'OK', 'Error') | Out-Null
        return
    }
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'Configurazione automatica accesso esterno'
    $dialog.Size = New-Object Drawing.Size(610, 390)
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = New-Object Drawing.Font('Segoe UI', 10)

    $intro = New-Object Windows.Forms.Label
    $intro.Text = "ATTENZIONE: il punto 1 va eseguito soltanto sul PC REMOTO che vuoi comandare.`r`nQuesto PC: $env:COMPUTERNAME - RustDesk: $localId`r`nNessuna porta verra aperta sulla Vodafone Station."
    $intro.Location = New-Object Drawing.Point(20, 18)
    $intro.Size = New-Object Drawing.Size(555, 72)

    $prepareButton = New-Object Windows.Forms.Button
    $prepareButton.Text = '1. PREPARA QUESTO PC REMOTO DA CONTROLLARE'
    $prepareButton.Location = New-Object Drawing.Point(20, 105)
    $prepareButton.Size = New-Object Drawing.Size(555, 58)
    $prepareButton.BackColor = [Drawing.Color]::FromArgb(21, 128, 61)
    $prepareButton.ForeColor = [Drawing.Color]::White
    $prepareButton.FlatStyle = 'Flat'

    $importButton = New-Object Windows.Forms.Button
    $importButton.Text = '2. IMPORTA SUL PC DI CONTROLLO'
    $importButton.Location = New-Object Drawing.Point(20, 180)
    $importButton.Size = New-Object Drawing.Size(555, 58)
    $importButton.BackColor = [Drawing.Color]::FromArgb(30, 64, 175)
    $importButton.ForeColor = [Drawing.Color]::White
    $importButton.FlatStyle = 'Flat'

    $wizardStatus = New-Object Windows.Forms.Label
    $wizardStatus.Text = 'Il punto 1 copia automaticamente la configurazione negli appunti. Sul secondo PC seleziona il computer e premi il punto 2.'
    $wizardStatus.Location = New-Object Drawing.Point(20, 260)
    $wizardStatus.Size = New-Object Drawing.Size(555, 54)
    $wizardStatus.ForeColor = [Drawing.Color]::DimGray

    $prepareButton.Add_Click({
        try {
            $installer = Join-Path $PSScriptRoot 'Install-VargaRemote-PowerAgent.ps1'
            if (-not (Test-Path $installer)) { throw 'Installer Power Agent non trovato.' }
            $wizardStatus.Text = 'Installazione in corso. Conferma la richiesta amministratore e completa l accesso Tailscale nel browser.'
            [Windows.Forms.Application]::DoEvents()
            $process = Start-Process powershell.exe -Verb RunAs -PassThru -Wait -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $installer), '-Automatic'
            )
            if ($process.ExitCode -ne 0) { throw "Preparazione non completata: codice $($process.ExitCode)." }
            if (-not [Windows.Forms.Clipboard]::ContainsText() -or -not [Windows.Forms.Clipboard]::GetText().StartsWith('VRE1:')) {
                throw 'Configurazione non trovata negli appunti. Riprova il punto 1.'
            }
            $wizardStatus.Text = 'QUESTO PC E PRONTO. Configurazione copiata. Passa ora al PC di controllo.'
            [Windows.Forms.MessageBox]::Show(
                'Preparazione completata. La configurazione e negli appunti. Sul PC di controllo seleziona questo computer e premi IMPORTA.',
                'Accesso esterno', 'OK', 'Information') | Out-Null
        }
        catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Preparazione automatica', 'OK', 'Error') | Out-Null }
    })

    $importButton.Add_Click({
        try {
            $device = Get-SelectedDevice
            if (-not $device) { return }
            if (-not [Windows.Forms.Clipboard]::ContainsText()) { throw 'Appunti vuoti. Esegui prima PREPARA sul PC da controllare.' }
            $payload = ConvertFrom-VargaExternalPairingCode -Code ([Windows.Forms.Clipboard]::GetText())
            $pairedRustDeskId = [string](Get-VargaObjectValue $payload 'rustDeskId' '')
            if ($pairedRustDeskId -and -not $pairedRustDeskId.Equals((Get-DeviceValue $device 'id'), [StringComparison]::OrdinalIgnoreCase)) {
                throw "Configurazione del PC sbagliato. Hai selezionato $((Get-DeviceValue $device 'name')) (ID $((Get-DeviceValue $device 'id'))), ma i dati appartengono al PC $([string](Get-VargaObjectValue $payload 'computerName' '')) (ID $pairedRustDeskId)."
            }
            $powerUri = [Uri]([string]$payload.powerUrl)
            $tailscale = Get-VargaTailscalePath
            if ($tailscale) {
                $localTailIps = @(& $tailscale ip -4 2>$null | ForEach-Object { ([string]$_).Trim() })
                if ($localTailIps -contains $powerUri.Host) {
                    throw 'Hai preparato il PC di controllo. Collegati prima al PC remoto con RustDesk ed esegui li il punto 1.'
                }
            }
            $wizardStatus.Text = 'Configurazione letta. Ricerca automatica di Varga Relay nella rete Tailscale...'
            [Windows.Forms.Application]::DoEvents()
            $relayUrl = Find-VargaRelay -Token ([string]$payload.token)
            Save-VargaExternalAccessConfig -DeviceId (Get-DeviceValue $device 'id') -RelayUrl $relayUrl `
                -PowerUrl ([string]$payload.powerUrl) -Token ([string]$payload.token) `
                -RustDeskPassword ([string](Get-VargaObjectValue $payload 'rustDeskPassword' ''))
            $dialog.DialogResult = [Windows.Forms.DialogResult]::OK
            $dialog.Close()
            if ($relayUrl) {
                $statusLabel.Text = 'Accesso esterno completo: accensione e spegnimento pronti.'
                [Windows.Forms.MessageBox]::Show('Configurazione completata. Power Agent e Varga Relay rilevati automaticamente.', 'Accesso esterno', 'OK', 'Information') | Out-Null
            }
            else {
                $statusLabel.Text = 'Spegnimento esterno pronto. Per ACCENDI manca il dispositivo Varga Relay.'
                [Windows.Forms.MessageBox]::Show(
                    'Power Agent configurato automaticamente. SPEGNI e RIAVVIA sono pronti. Per ACCENDI da PC spento manca ancora il dispositivo Varga Relay sempre acceso.',
                    'Configurazione parziale', 'OK', 'Warning') | Out-Null
            }
        }
        catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Importazione automatica', 'OK', 'Error') | Out-Null }
    })

    $dialog.Controls.AddRange(@($intro, $prepareButton, $importButton, $wizardStatus))
    [void]$dialog.ShowDialog($form)
})

$updateButton.Add_Click({
    if (-not (Test-Path $updateScriptPath)) {
        [Windows.Forms.MessageBox]::Show('Modulo di aggiornamento non disponibile.', 'Varga Remote', 'OK', 'Error') | Out-Null
        return
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $updateScriptPath), '-Force'
    )
})

$list.Add_DoubleClick({ $connect.PerformClick() })
Refresh-List
if (Test-Path $updateScriptPath) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', ('"{0}"' -f $updateScriptPath), '-Silent'
    )
}
[void]$form.ShowDialog()
