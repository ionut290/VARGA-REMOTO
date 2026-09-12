#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Silent,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repository = 'ionut290/VARGA-REMOTO'
$installRoot = $PSScriptRoot
$dataRoot = Join-Path $env:LOCALAPPDATA 'VargaRemote'
$statePath = Join-Path $dataRoot 'update-state.json'
$manifestPath = Join-Path $installRoot 'version.json'
$checkIntervalHours = 6

function Show-VargaUpdateMessage([string]$Message, [string]$Icon = 'Information') {
    if ($Silent) { return }
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show($Message, 'Aggiornamento Varga Remote', 'OK', $Icon) | Out-Null
}

function Write-VargaUpdateState([string]$Result, [string]$AvailableVersion = '') {
    New-Item -Path $dataRoot -ItemType Directory -Force | Out-Null
    [PSCustomObject]@{
        lastCheck = (Get-Date).ToUniversalTime().ToString('o')
        result = $Result
        availableVersion = $AvailableVersion
    } | ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8
}

try {
    if (-not (Test-Path $manifestPath)) {
        throw 'Manifest locale version.json non trovato.'
    }

    if ($Silent -and -not $Force -and (Test-Path $statePath)) {
        try {
            $state = Get-Content $statePath -Raw | ConvertFrom-Json
            $lastCheck = [DateTime]::Parse([string]$state.lastCheck).ToUniversalTime()
            if (((Get-Date).ToUniversalTime() - $lastCheck).TotalHours -lt $checkIntervalHours) {
                exit 0
            }
        }
        catch { }
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'VargaRemote-Updater' }
    $remoteManifestUrl = "https://raw.githubusercontent.com/$repository/main/windows/version.json"
    $remoteManifest = Invoke-RestMethod -Uri $remoteManifestUrl -Headers $headers
    $localManifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

    $localVersion = [Version]([string]$localManifest.versionNumber)
    $remoteVersion = [Version]([string]$remoteManifest.versionNumber)
    if (-not $Force -and $remoteVersion -le $localVersion) {
        Write-VargaUpdateState -Result 'up-to-date' -AvailableVersion ([string]$remoteManifest.version)
        Show-VargaUpdateMessage "Varga Remote $($localManifest.version) e gia aggiornato."
        exit 0
    }

    if ([string]$remoteManifest.repository -ne $repository) {
        throw 'Il manifest remoto non appartiene al repository ufficiale previsto.'
    }

    $tempRoot = Join-Path $env:TEMP ("VargaRemote-Update-" + [Guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $tempRoot 'update.zip'
    $extractPath = Join-Path $tempRoot 'extract'
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

    try {
        $archiveUrl = "https://github.com/$repository/archive/refs/heads/main.zip"
        Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -Headers $headers
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        $sourceRoot = Get-ChildItem -Path $extractPath -Directory |
            Select-Object -First 1 -ExpandProperty FullName
        $sourceWindows = Join-Path $sourceRoot 'windows'
        if (-not (Test-Path $sourceWindows)) {
            throw 'La cartella windows non e presente nel pacchetto scaricato.'
        }

        foreach ($relativeFile in @($remoteManifest.files)) {
            $candidate = Join-Path $sourceWindows ([string]$relativeFile)
            if (-not (Test-Path $candidate -PathType Leaf)) {
                throw "Aggiornamento incompleto: manca $relativeFile."
            }
        }

        $backupRoot = Join-Path $dataRoot 'UpdateBackup'
        New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
        Get-ChildItem -Path $installRoot -File -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $backupRoot $_.Name) -Force
        }

        foreach ($relativeFile in @($remoteManifest.files)) {
            Copy-Item -Path (Join-Path $sourceWindows ([string]$relativeFile)) `
                -Destination (Join-Path $installRoot ([string]$relativeFile)) -Force
        }
        foreach ($optionalFile in @('VargaRemote.ico', 'VargaRemote.svg')) {
            $optionalSource = Join-Path $sourceWindows $optionalFile
            if (Test-Path $optionalSource) {
                Copy-Item -Path $optionalSource -Destination (Join-Path $installRoot $optionalFile) -Force
            }
        }

        # Se il Power Agent e gia installato, aggiorna anche la copia eseguita
        # come SYSTEM in ProgramData e riavvia l'attivita pianificata.
        $powerAgentConfig = Join-Path $env:ProgramData 'VargaRemote\power-agent.json'
        $installedPowerAgent = Join-Path $env:ProgramData 'VargaRemote\VargaRemote-PowerAgent.ps1'
        $newPowerAgent = Join-Path $installRoot 'VargaRemote-PowerAgent.ps1'
        if ((Test-Path $powerAgentConfig) -and (Test-Path $newPowerAgent)) {
            $agentUpdated = $false
            try {
                Copy-Item -Path $newPowerAgent -Destination $installedPowerAgent -Force
                & schtasks.exe /End /TN 'Varga Remote Power Agent' 2>$null | Out-Null
                & schtasks.exe /Run /TN 'Varga Remote Power Agent' 2>$null | Out-Null
                $agentUpdated = $true
            }
            catch { }
            if (-not $agentUpdated -and -not $Silent) {
                $agentInstaller = Join-Path $installRoot 'Install-VargaRemote-PowerAgent.ps1'
                $agentProcess = Start-Process powershell.exe -Verb RunAs -PassThru -Wait -ArgumentList @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $agentInstaller),
                    '-Automatic', '-RefreshOnly'
                )
                if ($agentProcess.ExitCode -ne 0) {
                    throw 'Aggiornamento del Power Agent non completato.'
                }
            }
        }

        $installMetadataPath = Join-Path $installRoot 'install.json'
        if (Test-Path $installMetadataPath) {
            try {
                $installMetadata = Get-Content $installMetadataPath -Raw | ConvertFrom-Json
                $installMetadata.version = [string]$remoteManifest.version
                $installMetadata | ConvertTo-Json -Depth 8 | Set-Content $installMetadataPath -Encoding UTF8
            }
            catch { }
        }

        Write-VargaUpdateState -Result 'updated' -AvailableVersion ([string]$remoteManifest.version)
        Show-VargaUpdateMessage "Aggiornamento completato alla versione $($remoteManifest.version). Riavvia Varga Remote per applicare tutte le modifiche."
    }
    finally {
        if (Test-Path $tempRoot) {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-VargaUpdateState -Result ('error: ' + $_.Exception.Message)
    Show-VargaUpdateMessage ("Aggiornamento non riuscito:`r`n" + $_.Exception.Message) 'Error'
    exit 1
}
