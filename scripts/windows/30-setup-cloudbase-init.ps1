# Installs Cloudbase-Init (https://cloudbase.it/cloudbase-init/) — the
# Windows re-implementation of cloud-init — and configures it for the
# NoCloud and OpenStack ConfigDrive metadata services so the same image
# works under libvirt/QEMU and Proxmox VE.
#
# sysprep itself is NOT run here; packer's shutdown_command runs
# `sysprep /generalize` after provisioning. On first boot of a cloned VM,
# cloudbase-init applies hostname, Administrator password, ssh public keys
# and userdata scripts from the cloud-init drive.
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$', 'ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$', 'ERROR EXCEPTION: $1' | Write-Host
    Exit 1
}

[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$cbHome = 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init'
$cbConfPath = "$cbHome\conf\cloudbase-init.conf"

# OFFLINE: install the MSI from <cd>:\payloads\CloudbaseInitSetup.msi
# (the guest has no working TCP under QEMU).
$msi = $null
$cdDrives = @('C:\provision') + (Get-CimInstance Win32_Volume -Filter "DriveType=5" | ForEach-Object { "${($_.DriveLetter)}:" })
if ($cdDrives.Count -eq 1) { $cdDrives += 'D','E','F','G','H' }
foreach ($d in $cdDrives) {
    foreach ($p in "$d\payloads\CloudbaseInitSetup.msi", "$d\CloudbaseInitSetup.msi") {
        if (Test-Path $p) { $msi = $p; break }
    }
    if ($msi) { break }
}
if (-not $msi) {
    # see https://github.com/cloudbase/cloudbase-init/releases
    $cbVersion = '1.1.8'
    $artifactUrl = "https://github.com/cloudbase/cloudbase-init/releases/download/$cbVersion/CloudbaseInitSetup_$($cbVersion -replace '\.','_')_x64.msi"
    $msi = "$env:TEMP\$(Split-Path -Leaf $artifactUrl)"
    Write-Host "cloudbase-init payload not on the ISO — downloading $artifactUrl ..."
    Invoke-WebRequest $artifactUrl -OutFile $msi
}

Write-Host 'Installing cloudbase-init...'
# NB no SYSPREP property: we generalize ourselves in the shutdown command.
msiexec /i $msi /qn /l*v "$msi.log" | Out-Null
if ($LASTEXITCODE) { throw "cloudbase-init msi failed with exit code $LASTEXITCODE (see $msi.log)" }
Remove-Item $msi

# metadata services: NoCloud (libvirt/plain qemu, Proxmox nocloud) first,
# then the OpenStack ConfigDrive format Proxmox emits with
# `qm set <id> --citype configdrive2` (carries admin_pass for the
# Administrator password and ssh public keys).
$metadataServices = @(
    'cloudbaseinit.metadata.services.nocloudservice.NoCloudConfigDriveService',
    'cloudbaseinit.metadata.services.configdrive.ConfigDriveService'
)

# use the installer's default plugin list (hostname, create user, set
# password, ssh keys, extend volumes, local scripts, userdata, ...).
$plugins = &"$cbHome\Python\python.exe" -c @"
import json
from cloudbaseinit import conf as cloudbaseinit_conf
print(json.dumps(cloudbaseinit_conf.CONF.plugins))
"@ | ConvertFrom-Json

Write-Host 'Writing cloudbase-init.conf...'
Move-Item $cbConfPath "$cbConfPath.orig" -Force
Set-Content -Encoding ascii $cbConfPath @"
[DEFAULT]
username=Administrator
groups=Administrators
first_logon_behaviour=no
inject_user_password=true
debug=true
log_dir=$cbHome\log\
log_file=cloudbase-init.log
bsdtar_path=$cbHome\bin\bsdtar.exe
mtools_path=$cbHome\bin\
check_latest_version=false
plugins=$($plugins -join ",`n         ")
metadata_services=$($metadataServices -join ",`n                  ")

[config_drive]
locations=cdrom
types=iso
"@

# sshd needs fresh host keys on every clone — sysprep /generalize does not
# remove them, and 99-cleanup deletes them before sealing. Regenerate them
# via a cloudbase-init LocalScript (runs before userdata on first boot).
$localScripts = "$cbHome\LocalScripts"
New-Item -ItemType Directory -Force $localScripts | Out-Null
Set-Content -Encoding ascii "$localScripts\00-ssh-hostkeys.ps1" @'
$sshConfig = "C:\ProgramData\ssh"
$sshKeygen = @(
    "C:\Windows\System32\OpenSSH\ssh-keygen.exe",
    "C:\Program Files\OpenSSH\ssh-keygen.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($sshKeygen -and -not (Test-Path "$sshConfig\ssh_host_ed25519_key")) {
    & $sshKeygen -A
    Restart-Service sshd -ErrorAction SilentlyContinue
}
'@

Write-Host 'Done installing cloudbase-init.'
