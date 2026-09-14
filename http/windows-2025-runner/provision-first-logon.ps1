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
# Install the PowerShell/Win32-OpenSSH release (more predictable than the
# inbox capability, which on eval media can require a reboot before sshd
# registers). Removes any Windows-provided OpenSSH first.
$openSshBin = 'C:\Program Files\OpenSSH'
$openSshConfigHome = 'C:\ProgramData\ssh'

$existing = Get-WindowsCapability -Online -Name 'OpenSSH.*' | Where-Object { $_.State -ne 'NotPresent' }
if ($existing) {
    Write-Host 'Removing the Windows-provided OpenSSH capabilities...'
    $existing | Remove-WindowsCapability -Online | Out-Null
}

# see https://github.com/PowerShell/Win32-OpenSSH/releases
$openSshVersion = '10.0.0.0p2-Preview'
$zip = "$env:TEMP\OpenSSH-Win64.zip"
while ($true) {
    try {
        Invoke-WebRequest `
            -Uri "https://github.com/PowerShell/Win32-OpenSSH/releases/download/$openSshVersion/OpenSSH-Win64.zip" `
            -OutFile $zip
        break
    } catch {
        Write-Host "openssh download failed ($_), retrying..."
        Start-Sleep -Seconds 5
    }
}
Expand-Archive $zip 'C:\Program Files'
if (Test-Path 'C:\Program Files\OpenSSH-Win64') {
    Move-Item 'C:\Program Files\OpenSSH-Win64' $openSshBin
}
Remove-Item $zip
[Environment]::SetEnvironmentVariable(
    'PATH',
    "$([Environment]::GetEnvironmentVariable('PATH', 'Machine'));$openSshBin",
    'Machine')

# relax the default sshd_config the service will copy on first start:
# administrators use ~/.ssh/authorized_keys (not the separate file) and
# skip reverse DNS.
$sshdConfig = Get-Content -Raw "$openSshBin\sshd_config_default"
$sshdConfig = $sshdConfig `
    -replace '(?m)^(Match Group administrators.*)', '#$1' `
    -replace '(?m)^(\s*AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys.*)', '#$1' `
    -replace '(?m)^#?\s*UseDNS .+', 'UseDNS no'
Set-Content -Encoding ascii -NoNewline -Path "$openSshBin\sshd_config_default" -Value $sshdConfig

& "$openSshBin\install-sshd.ps1" -Confirm:$false

# wait for host keys + config to be generated, then restart cleanly.
Start-Service sshd
$deadline = (Get-Date).AddMinutes(3)
while ((Get-Date) -lt $deadline) {
    $ready = @('ssh_host_ed25519_key', 'sshd_config') | ForEach-Object {
        $f = "$openSshConfigHome\$_"
        (Test-Path $f) -and (Get-Item $f).Length -gt 0
    } | Where-Object { -not $_ }
    if (-not $ready) { break }
    Start-Sleep -Seconds 3
}
Stop-Service sshd -Force -ErrorAction SilentlyContinue

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
