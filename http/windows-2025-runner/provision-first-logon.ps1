# Runs from FirstLogonCommands (autounattend.xml), elevated as the local
# `packer` user on the provision ISO. Brings up OpenSSH so packer can take
# over the rest of the provisioning. Everything is logged because there is
# no interactive user to watch the console.
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

Start-Transcript -Path 'C:\Windows\Temp\first-logon.log' -Append | Out-Null

trap {
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$', 'ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$', 'ERROR EXCEPTION: $1' | Write-Host
    Stop-Transcript | Out-Null
    Exit 1
}

[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# --- OpenSSH -------------------------------------------------------------
# Server 2025 ships OpenSSH Server as an inbox capability; the payload is
# staged locally so no Windows Update access is required. Fall back to the
# Win32-OpenSSH release zip if the capability is not present.
$openSshCapability = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~*'
if ($openSshCapability -and $openSshCapability.State -ne 'NotPresent') {
    Write-Host 'Installing the inbox OpenSSH.Server capability...'
    Add-WindowsCapability -Online -Name $openSshCapability.Name | Out-Null
    $openSshBin = 'C:\Windows\System32\OpenSSH'
} else {
    Write-Host 'Inbox capability unavailable; installing Win32-OpenSSH...'
    $openSshBin = 'C:\Program Files\OpenSSH'
    $version = '9.8.3.0p1-Preview'
    $zip = "$env:TEMP\OpenSSH-Win64.zip"
    Invoke-WebRequest `
        -Uri "https://github.com/PowerShell/Win32-OpenSSH/releases/download/$version/OpenSSH-Win64.zip" `
        -OutFile $zip
    Expand-Archive $zip 'C:\Program Files'
    Move-Item 'C:\Program Files\OpenSSH-Win64' $openSshBin
    [Environment]::SetEnvironmentVariable(
        'PATH',
        "$([Environment]::GetEnvironmentVariable('PATH', 'Machine'));$openSshBin",
        'Machine')
    & "$openSshBin\install-sshd.ps1" -Confirm:$false
    Remove-Item $zip
}

Write-Host 'Configuring and starting sshd...'
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
        -DisplayName 'OpenSSH Server (sshd)' `
        -Protocol TCP -LocalPort 22 -Direction Inbound -Action Allow | Out-Null
} else {
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True
}

# powershell over ssh (matches how the linux images behave for packer).
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
    -PropertyType String -Force | Out-Null

Set-Service sshd -StartupType Automatic
sc.exe failure sshd reset= 0 actions= restart/60000 | Out-Null
Start-Service sshd

# --- stop the autologon ---------------------------------------------------
# LogonCount=1 in autounattend.xml already expires after this session; also
# clear the flag and any stored default credentials.
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $winlogon -Name AutoAdminLogon -Value 0
'AutoLogonCount', 'DefaultUserName', 'DefaultPassword' | ForEach-Object {
    Remove-ItemProperty -Path $winlogon -Name $_ -ErrorAction SilentlyContinue
}

Write-Host 'First-logon bootstrap complete; sshd is listening.'
Stop-Transcript | Out-Null
logoff
