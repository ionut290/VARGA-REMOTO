Set-StrictMode -Version Latest

function Test-VargaRemoteAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-VargaRemoteRustDeskPath {
    $candidatePaths = @()
    if ($env:ProgramFiles) {
        $candidatePaths += Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'
    }
    if (${env:ProgramFiles(x86)}) {
        $candidatePaths += Join-Path ${env:ProgramFiles(x86)} 'RustDesk\rustdesk.exe'
    }
    if ($env:LOCALAPPDATA) {
        $candidatePaths += Join-Path $env:LOCALAPPDATA 'Programs\RustDesk\rustdesk.exe'
    }
    $candidates = @($candidatePaths | Where-Object { Test-Path $_ })

    if ($candidates.Length -gt 0) {
        return $candidates[0]
    }

    $command = Get-Command rustdesk.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function ConvertFrom-VargaRemoteSecureString {
    param([Parameter(Mandatory)][Security.SecureString]$SecureString)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function New-VargaRemotePassword {
    param([int]$Length = 48)
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] $Length
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}
