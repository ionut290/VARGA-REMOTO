#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$powerToolsPath = Join-Path $PSScriptRoot 'PowerTools.ps1'
if (Test-Path $powerToolsPath) { . $powerToolsPath }
$smartWakePath = Join-Path $PSScriptRoot 'SmartWake.ps1'
if (Test-Path $smartWakePath) { . $smartWakePath }

if (-not (Test-VargaRemoteAdministrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-STA', '-File', ('"{0}"' -f $PSCommandPath)
    )
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = 'Installazione Varga Remote'
$form.Size = New-Object Drawing.Size(680, 650)
$form.MinimumSize = New-Object Drawing.Size(680, 650)
$form.MaximumSize = New-Object Drawing.Size(680, 650)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::FromArgb(15, 23, 42)
$form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

$title = New-Object Windows.Forms.Label
$title.Text = 'Varga Remote'
$title.Font = New-Object Drawing.Font('Segoe UI Semibold', 26)
$title.ForeColor = [Drawing.Color]::FromArgb(45, 212, 191)
$title.Location = New-Object Drawing.Point(30, 22)
$title.AutoSize = $true
$form.Controls.Add($title)

$intro = New-Object Windows.Forms.Label
$intro.Text = 'Installa accesso remoto permanente e configura Smart Wake automaticamente.'
$intro.ForeColor = [Drawing.Color]::FromArgb(203, 213, 225)
$intro.Location = New-Object Drawing.Point(34, 75)
$intro.AutoSize = $true
$form.Controls.Add($intro)

function Add-FieldLabel([string]$text, [int]$top) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object Drawing.Point(34, $top)
    $label.AutoSize = $true
    $form.Controls.Add($label)
}

Add-FieldLabel 'Nome del computer' 118
$nameBox = New-Object Windows.Forms.TextBox
$nameBox.Location = New-Object Drawing.Point(34, 145)
$nameBox.Size = New-Object Drawing.Size(596, 30)
$nameBox.Text = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'VARGA PC' }
$form.Controls.Add($nameBox)

Add-FieldLabel 'Password permanente (almeno 12 lettere o numeri)' 188
$passwordBox = New-Object Windows.Forms.TextBox
$passwordBox.Location = New-Object Drawing.Point(34, 215)
$passwordBox.Size = New-Object Drawing.Size(286, 30)
$passwordBox.UseSystemPasswordChar = $true
$form.Controls.Add($passwordBox)

$confirmBox = New-Object Windows.Forms.TextBox
$confirmBox.Location = New-Object Drawing.Point(344, 215)
$confirmBox.Size = New-Object Drawing.Size(286, 30)
$confirmBox.UseSystemPasswordChar = $true
$form.Controls.Add($confirmBox)

$confirmHint = New-Object Windows.Forms.Label
$confirmHint.Text = 'Ripeti la password nel secondo campo.'
$confirmHint.Location = New-Object Drawing.Point(344, 248)
$confirmHint.ForeColor = [Drawing.Color]::FromArgb(148, 163, 184)
$confirmHint.AutoSize = $true
$form.Controls.Add($confirmHint)

$consentBox = New-Object Windows.Forms.CheckBox
$consentBox.Text = 'Confermo di essere il proprietario del PC o di avere autorizzazione.'
$consentBox.Location = New-Object Drawing.Point(34, 288)
$consentBox.Size = New-Object Drawing.Size(600, 32)
$consentBox.ForeColor = [Drawing.Color]::White
$form.Controls.Add($consentBox)

$installButton = New-Object Windows.Forms.Button
$installButton.Text = 'INSTALLA VARGA REMOTE'
$installButton.Location = New-Object Drawing.Point(34, 335)
$installButton.Size = New-Object Drawing.Size(596, 48)
$installButton.FlatStyle = 'Flat'
$installButton.FlatAppearance.BorderSize = 0
$installButton.BackColor = [Drawing.Color]::FromArgb(13, 148, 136)
$installButton.ForeColor = [Drawing.Color]::White
$installButton.Font = New-Object Drawing.Font('Segoe UI Semibold', 11)
$form.Controls.Add($installButton)

$progress = New-Object Windows.Forms.ProgressBar
$progress.Location = New-Object Drawing.Point(34, 399)
$progress.Size = New-Object Drawing.Size(596, 12)
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 0
$form.Controls.Add($progress)

$status = New-Object Windows.Forms.Label
$status.Text = 'Pronto per installare.'
$status.Location = New-Object Drawing.Point(34, 425)
$status.Size = New-Object Drawing.Size(596, 25)
$status.ForeColor = [Drawing.Color]::FromArgb(94, 234, 212)
$form.Controls.Add($status)

$log = New-Object Windows.Forms.TextBox
$log.Location = New-Object Drawing.Point(34, 455)
$log.Size = New-Object Drawing.Size(596, 90)
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.BackColor = [Drawing.Color]::FromArgb(2, 6, 23)
$log.ForeColor = [Drawing.Color]::FromArgb(203, 213, 225)
$log.BorderStyle = 'FixedSingle'
$form.Controls.Add($log)

$openButton = New-Object Windows.Forms.Button
$openButton.Text = 'APRI VARGA REMOTE'
$openButton.Location = New-Object Drawing.Point(34, 560)
$openButton.Size = New-Object Drawing.Size(286, 40)
$openButton.Visible = $false
$openButton.FlatStyle = 'Flat'
$openButton.BackColor = [Drawing.Color]::FromArgb(13, 148, 136)
$openButton.ForeColor = [Drawing.Color]::White
$form.Controls.Add($openButton)

$closeButton = New-Object Windows.Forms.Button
$closeButton.Text = 'CHIUDI'
$closeButton.Location = New-Object Drawing.Point(344, 560)
$closeButton.Size = New-Object Drawing.Size(286, 40)
$closeButton.Visible = $false
$closeButton.FlatStyle = 'Flat'
$closeButton.BackColor = [Drawing.Color]::FromArgb(51, 65, 85)
$closeButton.ForeColor = [Drawing.Color]::White
$form.Controls.Add($closeButton)

function Set-InstallerStatus([string]$message) {
    $status.Text = $message
    $log.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $message`r`n")
    $log.SelectionStart = $log.TextLength
    $log.ScrollToCaret()
    [Windows.Forms.Application]::DoEvents()
}

function Find-RustDeskService {
    return @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like '*RustDesk*' -or $_.DisplayName -like '*RustDesk*'
    })
}

function Install-RustDeskEngine {
    $existing = Get-VargaRemoteRustDeskPath
    if ($existing) {
        Set-InstallerStatus 'Motore RustDesk gia installato.'
        return $existing
    }

    Set-InstallerStatus 'Download del motore remoto ufficiale...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'VargaRemote-Installer' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/rustdesk/rustdesk/releases/latest' -Headers $headers
    $asset = $release.assets | Where-Object {
        $_.name -match 'x86_64\.exe$' -and $_.name -notmatch 'portable'
    } | Select-Object -First 1
    if (-not $asset) { throw 'Installer Windows x64 non trovato.' }

    $downloadPath = Join-Path $env:TEMP 'VargaRemote-RustDesk-Setup.exe'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -Headers $headers
    Set-InstallerStatus 'Installazione automatica del servizio...'
    $installer = Start-Process -FilePath $downloadPath -ArgumentList '--silent-install' -PassThru

    $installed = $null
    for ($second = 0; $second -lt 120 -and -not $installed; $second++) {
        Start-Sleep -Seconds 1
        $installed = Get-VargaRemoteRustDeskPath
        $services = @(Find-RustDeskService)
        if ($installed -and $services.Length -gt 0) { break }
        if (($second % 10) -eq 9) {
            Set-InstallerStatus "Installazione in corso... $($second + 1) secondi"
        }
    }

    if (-not $installed) {
        throw 'Installazione non completata entro 2 minuti.'
    }
    if (-not $installer.HasExited) {
        Stop-Process -Id $installer.Id -Force -ErrorAction SilentlyContinue
    }
    Set-InstallerStatus 'Motore remoto installato.'
    return $installed
}

function Install-VargaRemoteFiles {
    param(
        [Parameter(Mandatory)][string]$RustDeskPath,
        [Parameter(Mandatory)][string]$ComputerLabel,
        [Parameter(Mandatory)][string]$RustDeskId,
        $SmartWakeProfile = $null
    )

    $installRoot = Join-Path $env:LOCALAPPDATA 'VargaRemote\App'
    New-Item -Path $installRoot -ItemType Directory -Force | Out-Null
    Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $installRoot $_.Name) -Force
    }
    Get-ChildItem -Path $PSScriptRoot -Filter '*.json' | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $installRoot $_.Name) -Force
    }
    $sourceIcon = Join-Path $PSScriptRoot 'VargaRemote.ico'
    if (Test-Path $sourceIcon) {
        Copy-Item -Path $sourceIcon -Destination (Join-Path $installRoot 'VargaRemote.ico') -Force
    }

    $smartMethod = ''
    $smartLabel = ''
    $smartState = ''
    $ethernetMac = ''
    if ($SmartWakeProfile) {
        $recommendation = Get-VargaObjectValue $SmartWakeProfile 'Recommendation' $null
        $networkInfo = Get-VargaObjectValue $SmartWakeProfile 'Network' $null
        $smartMethod = [string](Get-VargaObjectValue $recommendation 'Method' '')
        $smartLabel = [string](Get-VargaObjectValue $recommendation 'Label' '')
        $smartState = [string](Get-VargaObjectValue $recommendation 'RemoteState' '')
        $ethernetMac = [string](Get-VargaObjectValue $networkInfo 'EthernetMac' '')
    }

    $metadata = [PSCustomObject]@{
        app = 'Varga Remote'
        version = '0.6.0-beta'
        computerName = $ComputerLabel
        windowsName = $env:COMPUTERNAME
        rustDeskId = $RustDeskId
        smartWakeMethod = $smartMethod
        smartWakeLabel = $smartLabel
        installedAt = (Get-Date).ToString('o')
    }
    $metadata | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $installRoot 'install.json') -Encoding UTF8

    if ($SmartWakeProfile -and (Get-Command Save-VargaLocalSmartWakeProfile -ErrorAction SilentlyContinue)) {
        Save-VargaLocalSmartWakeProfile -Profile $SmartWakeProfile -Path (Join-Path $installRoot 'local-smart-wake.json') | Out-Null
        Save-VargaLocalSmartWakeProfile -Profile $SmartWakeProfile | Out-Null
    }

    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop 'Varga Remote.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $managerPath = Join-Path $installRoot 'VargaRemote-Manager.ps1'
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$managerPath`""
    $shortcut.WorkingDirectory = $installRoot
    $installedIcon = Join-Path $installRoot 'VargaRemote.ico'
    if (Test-Path $installedIcon) { $shortcut.IconLocation = "$installedIcon,0" }
    elseif (Test-Path $RustDeskPath) { $shortcut.IconLocation = "$RustDeskPath,0" }
    $shortcut.Description = 'Varga Remote - controllo PC autorizzato'
    $shortcut.Save()

    $infoPath = Join-Path $desktop 'Varga Remote - Dati PC.txt'
    @(
        'VARGA REMOTE - DATI DEL PC',
        "Nome: $ComputerLabel",
        "Nome Windows: $env:COMPUTERNAME",
        "ID RustDesk: $RustDeskId",
        "MAC Ethernet: $ethernetMac",
        "Smart Wake: $smartLabel",
        "Stato remoto: $smartState",
        "Installato: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        '',
        'La password non viene salvata in questo file.',
        'Per associare questo PC a un altro Varga Remote usa COPIA PROFILO.'
    ) | Set-Content -Path $infoPath -Encoding UTF8
    return $shortcutPath
}

$script:installedShortcut = $null
$installButton.Add_Click({
    if (-not $consentBox.Checked) {
        [Windows.Forms.MessageBox]::Show('Devi confermare di essere autorizzato.', 'Varga Remote', 'OK', 'Warning') | Out-Null
        return
    }
    $password = $passwordBox.Text
    if ($password -ne $confirmBox.Text) {
        [Windows.Forms.MessageBox]::Show('Le due password non coincidono.', 'Varga Remote', 'OK', 'Warning') | Out-Null
        return
    }
    if ($password.Length -lt 12 -or $password -notmatch '^[A-Za-z0-9]+$') {
        [Windows.Forms.MessageBox]::Show('Usa almeno 12 caratteri composti soltanto da lettere e numeri.', 'Varga Remote', 'OK', 'Warning') | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($nameBox.Text)) {
        [Windows.Forms.MessageBox]::Show('Inserisci il nome del computer.', 'Varga Remote', 'OK', 'Warning') | Out-Null
        return
    }

    $installButton.Enabled = $false
    $nameBox.Enabled = $false
    $passwordBox.Enabled = $false
    $confirmBox.Enabled = $false
    $consentBox.Enabled = $false
    $progress.MarqueeAnimationSpeed = 30

    try {
        $rustDesk = Install-RustDeskEngine
        Set-InstallerStatus 'Configurazione accesso permanente...'
        & $rustDesk --password $password | Out-Null
        $password = $null
        $passwordBox.Clear()
        $confirmBox.Clear()

        $services = @(Find-RustDeskService)
        foreach ($service in $services) {
            Set-Service -Name $service.Name -StartupType Automatic
            if ($service.Status -ne 'Running') { Start-Service -Name $service.Name }
        }

        Set-InstallerStatus 'Lettura ID del computer...'
        $id = $null
        for ($attempt = 0; $attempt -lt 15 -and -not $id; $attempt++) {
            $candidate = (& $rustDesk --get-id 2>$null | Out-String).Trim()
            if ($candidate -match '(?m)^\s*([A-Za-z][A-Za-z0-9-]{5,}|[0-9]{6,})\s*$') {
                $id = $matches[1]
            }
            if (-not $id) { Start-Sleep -Seconds 1 }
        }
        if (-not $id) { $id = 'Apri Varga Remote per visualizzare ID' }

        $smartWakeProfile = $null
        if (Get-Command Get-VargaLocalSmartWakeProfile -ErrorAction SilentlyContinue) {
            Set-InstallerStatus 'Smart Wake: configurazione Ethernet e analisi rete...'
            try {
                $smartWakeProfile = Get-VargaLocalSmartWakeProfile -DatabasePath (Join-Path $PSScriptRoot 'router-database.json') -Optimize
                $smartRecommendation = Get-VargaObjectValue $smartWakeProfile 'Recommendation' $null
                $smartLabel = [string](Get-VargaObjectValue $smartRecommendation 'Label' 'diagnostica completata')
                Set-InstallerStatus "Smart Wake: $smartLabel"
            }
            catch {
                Set-InstallerStatus "Smart Wake non completato: $($_.Exception.Message)"
            }
        }

        Set-InstallerStatus 'Creazione app sul Desktop...'
        $script:installedShortcut = Install-VargaRemoteFiles -RustDeskPath $rustDesk -ComputerLabel $nameBox.Text.Trim() -RustDeskId $id -SmartWakeProfile $smartWakeProfile
        Set-InstallerStatus "Installazione completata. ID: $id"
        $status.ForeColor = [Drawing.Color]::FromArgb(74, 222, 128)
        $openButton.Visible = $true
        $closeButton.Visible = $true

        $smartFinal = 'Smart Wake: diagnostica non disponibile.'
        if ($smartWakeProfile) {
            $smartRecommendation = Get-VargaObjectValue $smartWakeProfile 'Recommendation' $null
            $smartFinal = "Smart Wake: $([string](Get-VargaObjectValue $smartRecommendation 'Label' ''))`r`nStato remoto: $([string](Get-VargaObjectValue $smartRecommendation 'RemoteState' ''))"
        }
        [Windows.Forms.MessageBox]::Show(
            "Varga Remote e installato sul Desktop.`r`n`r`nID del PC: $id`r`n$smartFinal`r`n`r`nApri Varga Remote e usa COPIA PROFILO per associare questo PC.",
            'Installazione completata', 'OK', 'Information') | Out-Null
    }
    catch {
        $password = $null
        Set-InstallerStatus "ERRORE: $($_.Exception.Message)"
        $status.ForeColor = [Drawing.Color]::FromArgb(248, 113, 113)
        $installButton.Enabled = $true
        $nameBox.Enabled = $true
        $passwordBox.Enabled = $true
        $confirmBox.Enabled = $true
        $consentBox.Enabled = $true
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Installazione non riuscita', 'OK', 'Error') | Out-Null
    }
    finally {
        $progress.MarqueeAnimationSpeed = 0
    }
})

$openButton.Add_Click({
    if ($script:installedShortcut -and (Test-Path $script:installedShortcut)) {
        Start-Process $script:installedShortcut
    }
})
$closeButton.Add_Click({ $form.Close() })
[void]$form.ShowDialog()
