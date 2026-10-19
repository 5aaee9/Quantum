# Execute through SSH on a fresh ConfigDrive clone, after hostname reboot.
param([string]$ExpectedHostname = 'win11-smoke')
$ErrorActionPreference = 'Stop'
$os = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
if ($os.EditionID -ne 'Enterprise') { throw "Wrong edition: $($os.EditionID)" }
if ($env:COMPUTERNAME -ne $ExpectedHostname) { throw "Wrong hostname: $env:COMPUTERNAME" }
foreach ($name in 'packer', 'runner') {
    if (Get-LocalUser $name -ErrorAction SilentlyContinue) { throw "Build user remains: $name" }
}
if (Test-Path 'C:\actions-runner') { throw 'Runner payload remains' }
if (-not (Get-LocalUser Administrator).Enabled) { throw 'Administrator is disabled' }
if ((Get-Service QEMU-GA).Status -ne 'Running') { throw 'QEMU Guest Agent is not running' }
if ((Get-Service sshd).Status -ne 'Running') { throw 'OpenSSH is not running' }
if (-not (Get-NetAdapter | Where-Object Status -eq Up)) { throw 'No active network adapter' }
if (-not (Test-Path "$env:USERPROFILE\.ssh\authorized_keys")) { throw 'SSH keys not injected' }
if ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA -ne 1) {
    throw 'UAC was not restored'
}
if (-not (Get-Tpm).TpmPresent) { throw 'Clone TPM is absent' }
Write-Output "PASS: Windows 11 Enterprise $($os.CurrentBuild).$($os.UBR), hostname, SSH metadata, Guest Agent, network, UAC and TPM"
