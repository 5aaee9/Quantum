# Final provisioner. Stages C:\Windows\Temp\packer-sysprep-shutdown.ps1
# (invoked by packer's shutdown_command in a NEW ssh session — that is why
# user/key deletion lives there and not here) and cleans up the image.
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

# --- stage the sysprep shutdown script -------------------------------------
Set-Content -Encoding ascii 'C:\Windows\Temp\packer-sysprep-shutdown.ps1' @'
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\Windows\Temp\sysprep-shutdown.log" -Append | Out-Null

# unattend for the generalize pass.
Set-Content -Encoding ascii "C:\Windows\Temp\sysprep-unattend.xml" @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="generalize">
    <component name="Microsoft-Windows-PnpSysprep" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <PersistAllDeviceInstalls>false</PersistAllDeviceInstalls>
    </component>
  </settings>
</unattend>
"@

# remove per-machine ssh host keys; a cloudbase-init LocalScript
# regenerates them on first boot of a clone.
Stop-Service sshd -Force -ErrorAction SilentlyContinue
Remove-Item "C:\ProgramData\ssh\ssh_host_*" -Force -ErrorAction SilentlyContinue

# remove the temporary packer build account (this session stays alive;
# the account just will not exist on clones).
& net.exe user packer /delete

Write-Host "Running sysprep /generalize /oobe /shutdown ..."
& "C:\Windows\System32\Sysprep\sysprep.exe" /generalize /oobe /shutdown /unattend:"C:\Windows\Temp\sysprep-unattend.xml"
Stop-Transcript | Out-Null
'@

# --- restore the firewall ----------------------------------------------------
# The specialize pass disabled it so QEMU slirp hostfwd could reach sshd.
# Turn it back on for the final image; the explicit SSH inbound rule stays.
Write-Host 'Re-enabling Windows Firewall...'
netsh advfirewall set allprofiles state on | Out-Null

# --- clean transient state --------------------------------------------------
# NB keep packer-sysprep-shutdown.ps1 — shutdown_command runs it next.
Write-Host 'Cleaning temp files, event logs and download caches...'
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem 'C:\Windows\Temp' -Exclude 'packer-sysprep-shutdown.ps1' |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem 'C:\Windows\SoftwareDistribution\Download' -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
wevtutil el | ForEach-Object { wevtutil cl $_ 2>$null }

# zero free space so the qcow2 compresses well (same spirit as
# scripts/generic/99-release-disk-space.sh).
Write-Host 'Zeroing free disk space (this can take a while)...'
$sdelete = 'C:\Windows\Temp\sdelete-zero.bin'
try {
    $fs = New-Object IO.FileStream($sdelete, 'Create', 'Write')
    $buf = New-Object byte[] (16MB)
    while ($true) { $fs.Write($buf, 0, $buf.Length) }
} catch [System.IO.IOException] {
    # disk full — expected; that is the point.
} finally {
    if ($fs) { $fs.Close() }
    Remove-Item $sdelete -Force -ErrorAction SilentlyContinue
}

Write-Host 'Done. Packer will now run the sysprep shutdown command.'
