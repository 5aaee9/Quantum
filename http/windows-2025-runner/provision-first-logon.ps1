# Runs from FirstLogonCommands (autounattend.xml), elevated as the local
# `packer` user via the provision floppy. Brings up OpenSSH so packer can
# take over the rest of the provisioning. Everything is logged because
# there is no interactive user to watch the console.
#
# Mirrors rgl/windows-vagrant provision-openssh.ps1 (proven on QEMU/KVM):
# https://github.com/rgl/windows-vagrant
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

Start-Transcript -Path 'C:\Windows\Temp\first-logon.log' -Append | Out-Null

trap {
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$', 'ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$', 'ERROR EXCEPTION: $1' | Write-Host
    Stop-Transcript | Out-Null
    # leave the VM up for a while so a failed run can be inspected over VNC.
    Start-Sleep -Seconds (60*60)
    Exit 1
}

[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# --- OpenSSH -------------------------------------------------------------
# Install the PowerShell/Win32-OpenSSH release. Binaries land in
# $openSshHome; config, host keys and logs in $openSshConfigHome.
$openSshHome = 'C:\Program Files\OpenSSH'
$openSshConfigHome = 'C:\ProgramData\ssh'

Add-Type -AssemblyName System.IO.Compression.FileSystem

# uninstall the Windows provided OpenSSH binaries.
$windowsOpenSshCapabilities = Get-WindowsCapability -Online -Name 'OpenSSH.*' | Where-Object { $_.State -ne 'NotPresent' }
if ($windowsOpenSshCapabilities) {
    Write-Host 'Uninstalling the Windows OpenSSH Capabilities...'
    $windowsOpenSshCapabilities | Remove-WindowsCapability -Online | Out-Null
}

Write-Host 'Installing the PowerShell/Win32-OpenSSH binaries...'
# see https://github.com/PowerShell/Win32-OpenSSH/releases
# renovate: datasource=github-releases depName=PowerShell/Win32-OpenSSH
$openSshVersion = '10.0.0.0p2-Preview'
$localZipPath = "$env:TEMP\OpenSSH-Win64.zip"
while ($true) {
    try {
        (New-Object System.Net.WebClient).DownloadFile(
            "https://github.com/PowerShell/Win32-OpenSSH/releases/download/$openSshVersion/OpenSSH-Win64.zip",
            $localZipPath)
        break
    } catch {
        Write-Host "openssh download failed ($_), retrying..."
        Start-Sleep -Seconds 5
    }
}
if (Test-Path $openSshHome) {
    Remove-Item -Recurse -Force $openSshHome
}
[IO.Compression.ZipFile]::ExtractToDirectory($localZipPath, $openSshHome)
Remove-Item $localZipPath
Push-Location $openSshHome
Move-Item OpenSSH-Win64\* .
Remove-Item OpenSSH-Win64
.\ssh.exe -V
Pop-Location

# add the OpenSSH binaries to the system PATH.
[Environment]::SetEnvironmentVariable(
    'PATH',
    "$([Environment]::GetEnvironmentVariable('PATH', 'Machine'));$openSshHome",
    'Machine')

# remove any existing configuration.
if (Test-Path $openSshConfigHome) {
    Remove-Item -Recurse -Force $openSshConfigHome
}

# modify the default configuration.
# NB sshd, at startup, copies this file to $openSshConfigHome\sshd_config
#    when it does not already exist (fresh install).
$sshdConfig = Get-Content -Raw "$openSshHome\sshd_config_default"
# let Administrators also use ~/.ssh/authorized_keys.
# see https://github.com/PowerShell/Win32-OpenSSH/issues/1324
$sshdConfig = $sshdConfig `
    -replace '(?m)^(Match Group administrators.*)', '#$1' `
    -replace '(?m)^(\s*AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys.*)', '#$1'
# disable UseDNS.
$sshdConfig = $sshdConfig `
    -replace '(?m)^#?\s*UseDNS .+', 'UseDNS no'
Set-Content -Encoding ascii -NoNewline -Path "$openSshHome\sshd_config_default" -Value $sshdConfig

# install the service.
&"$openSshHome\install-sshd.ps1" -Confirm:$false

# start the service (it creates the configuration and host keys).
Start-Service sshd

# wait for all the files to be created.
while ($true) {
    $pendingFiles = @(
        'ssh_host_ecdsa_key.pub'
        'ssh_host_ecdsa_key'
        'ssh_host_ed25519_key.pub'
        'ssh_host_ed25519_key'
        'ssh_host_rsa_key.pub'
        'ssh_host_rsa_key'
        'sshd_config'
        'sshd.pid'
    ) | Where-Object {
        $filePath = "$openSshConfigHome\$_"
        !((Test-Path $filePath) -and (Get-Item $filePath).Length)
    }
    if (!$pendingFiles) {
        break
    }
    Start-Sleep -Seconds 5
}
Start-Sleep -Seconds 15
Stop-Service sshd

Write-Host 'Setting the host file permissions...'
&"$openSshHome\FixHostFilePermissions.ps1" -Confirm:$false

Write-Host 'Configuring sshd and ssh-agent services...'
# WARN do not change the startup type from delayed-auto to auto: the later
#      proved unreliable (sshd accepts the socket then stalls the banner).
$result = sc.exe config sshd start= delayed-auto
if ($result -ne '[SC] ChangeServiceConfig SUCCESS') {
    throw "sc.exe config sshd failed with $result"
}
$result = sc.exe failure sshd reset= 0 actions= restart/60000
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe failure sshd failed with $result"
}
$result = sc.exe failure ssh-agent reset= 0 actions= restart/60000
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe failure ssh-agent failed with $result"
}

# powershell over ssh (matches how the linux images behave for packer).
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
    -PropertyType String -Force | Out-Null

Write-Host 'Starting the sshd service...'
Start-Service sshd

Write-Host 'Allow firewall access to the sshd service port...'
New-NetFirewallRule -Protocol TCP -LocalPort 22 -Direction Inbound -Action Allow -DisplayName SSH | Out-Null

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
