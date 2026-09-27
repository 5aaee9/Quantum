# provision-first-logon.ps1 — FULLY OFFLINE Windows runner image provisioner.
#
# Why offline: this Windows Server 2025 guest cannot establish a single TCP
# connection under QEMU — we tried every NIC model (virtio NetKVM 2k22+2k25,
# e1000, e1000e, rtl8139) and every backend (slirp, tap); ICMP and UDP flow
# but TCP never emits a single segment. So packer uses communicator="none"
# and this script does ALL provisioning locally, then syspreps + powers off.
# Packer completes when QEMU exits.
#
# Payloads: specialize copies the provision CD to C:\provision\ (the CD drive
# letter is unstable / the CD may be gone by first-logon), so everything
# below reads from that fixed on-disk dir — no downloads, no network.
$ErrorActionPreference = 'Continue'   # never die — always reach sysprep+shutdown

# WRITE A BREADCRUMB FIRST — the simplest possible proof this script ran.
# Write to BOTH C:\Windows\Temp (always writable by any user) and C:\ so at
# least one survives. No Start-Transcript (it can block in first-logon).
foreach ($tf in 'C:\Windows\Temp\provision.trace','C:\provision.trace') {
    Set-Content $tf "start $(Get-Date -Format HH:mm:ss)" -Force -ErrorAction SilentlyContinue
}
# log to disk AND to COM1 — the serial port reaches QEMU's -serial file: so
# we get a live, host-readable trace of every step. The specialize COM1
# marker proves `cmd /c "echo X > COM1"` works from Windows under QEMU, so
# reuse exactly that mechanism (no `mode` — specialize's bare `echo`
# already wrote through, and `mode COM1` can block on some serial setups).
function Log($m) {
    $line = "$(Get-Date -Format HH:mm:ss) $m"
    Write-Host $line
    try { & cmd /c "echo PROV: $line > COM1" 2>$null | Out-Null } catch {}
    foreach ($tf in 'C:\Windows\Temp\provision.trace','C:\provision.trace') { Add-Content $tf -Value $line -ErrorAction SilentlyContinue }
}

# sentinel: if this already ran (a post-sysprep OOBE re-triggered
# FirstLogonCommands), just power off — never loop provision->sysprep->oobe.
if (Test-Path 'C:\provision-done.marker') {
    Log 'marker present — powering off'
    & shutdown /p /f | Out-Null
    return
}
New-Item 'C:\provision-done.marker' -ItemType File -Force | Out-Null

# we were invoked by the ProvisionOnBoot scheduled task (registered in
# specialize) — delete it now so a post-sysprep OOBE boot doesn't re-run us.
schtasks /delete /tn ProvisionOnBoot /f 2>$null | Out-Null

# DEAD-MAN SWITCH: a detached process that sleeps 25min then force-powers
# off. This is a separate powershell process guaranteed to fire — if
# provisioning hangs the VM still powers off so packer completes. Success
# path kills it via $watchdog below before the real sysprep+shutdown.
$watchdog = Start-Process powershell -PassThru -WindowStyle Hidden `
    -ArgumentList '-NoProfile','-Command','Start-Sleep 1500; shutdown /p /f' -ErrorAction SilentlyContinue
Log "watchdog armed: poweroff in 25min if provisioning hangs"

# resolve the payload dir: prefer the on-disk staging copy (C:\provision),
# else scan CD-ROM drives for the PROVISION volume.
$pv = $null
foreach ($cand in 'C:\provision', (Get-CimInstance Win32_Volume -Filter "DriveType=5" | ForEach-Object { "$($_.DriveLetter)\" })) {
    if (Test-Path "$cand\virtio-win-guest-tools.exe") { $pv = $cand.TrimEnd('\'); break }
}
if (-not $pv) { $pv = 'C:\provision' }
Log "provision content: $pv"
Get-CimInstance Win32_Volume | ForEach-Object { Log "  vol $($_.DriveLetter) label=$($_.FileSystemLabel) type=$($_.DriveType)" }

function Payload($name) {
    foreach ($p in "$pv\$name", "$pv\payloads\$name") {
        if (Test-Path $p) { return $p }
    }
    Log "  !! payload $name NOT FOUND"
    return $null
}

# run a command with a hard timeout so a hung installer can't stall the
# whole build (packer has a 90m shutdown_timeout — we must power off).
function Run($exe, [string[]]$argz, [int]$timeoutSec = 600) {
    Log "  > $exe $($argz -join ' ')"
    $proc = Start-Process -FilePath $exe -ArgumentList $argz -PassThru -NoNewWindow -ErrorAction SilentlyContinue
    if (-not $proc) { Log "  (could not start)"; return }
    if (-not $proc.WaitForExit($timeoutSec * 1000)) {
        Log "  (TIMEOUT after ${timeoutSec}s — killing)"
        try { $proc.Kill() } catch {}
    }
    Log "  (exit $($proc.ExitCode))"
}

Log '=== virtio drivers via pnputil (skip the guest-tools bundle — it hangs) ==='
# the virtio-win-guest-tools MSI wrapper hangs under this environment; just
# pnputil the individual .inf drivers instead (that's all we actually need).
foreach ($inf in (Get-ChildItem "$pv\*.inf" -ErrorAction SilentlyContinue)) {
    Run 'pnputil' @('/add-driver', $inf.FullName, '/install') 60
}
& pnputil /scan-devices 2>$null | Out-Null

Log '=== OpenSSH (sshd) ==='
$ossh = Payload 'OpenSSH-Win64.zip'
if ($ossh) {
    $sshHome = 'C:\Program Files\OpenSSH'
    Run 'powershell' @('-NoProfile','-Command',"Expand-Archive '$ossh' '$sshHome' -Force") 120
    $nested = Get-ChildItem $sshHome -Directory -Filter 'OpenSSH-Win64' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nested) { Get-ChildItem $nested.FullName | Move-Item $sshHome -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$sshHome\install-sshd.ps1") { Run 'powershell' @('-NoProfile','-File',"$sshHome\install-sshd.ps1") 120 }
    Set-Service sshd -StartupType Automatic -ErrorAction SilentlyContinue
    Set-Service ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
}

Log '=== git ==='
$git = Payload 'Git-64-bit.exe'
if ($git) { Run $git @('/VERYSILENT','/NORESTART','/NOCANCEL','/SP-','/SUPPRESSMSGBOXES') 300 }
if (Test-Path 'C:\Program Files\Git\bin\git.exe') {
    & 'C:\Program Files\Git\bin\git.exe' config --system --add safe.directory '*' 2>$null
    & 'C:\Program Files\Git\bin\git.exe' config --system core.longpaths true 2>$null
    & 'C:\Program Files\Git\bin\git.exe' config --system core.autocrlf false 2>$null
    & 'C:\Program Files\Git\bin\git.exe' config --system core.symlinks true 2>$null
}

Log '=== pwsh ==='
$pwsh = Payload 'PowerShell-win-x64.msi'
if ($pwsh) { Run 'msiexec' @('/i', $pwsh, '/qn', '/norestart', 'ADD_PATH=1', 'USE_MU=0', 'ENABLE_MU=0') 300 }

Log '=== cloudbase-init ==='
$cb = Payload 'CloudbaseInitSetup.msi'
if ($cb) { Run 'msiexec' @('/i', $cb, '/qn', '/norestart') 300 }
$cbHome = 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init'
if (Test-Path $cbHome) {
    # write cloudbase-init.conf with a hardcoded standard plugin list — the
    # `python -c "import cloudbaseinit; print(CONF.plugins)"` enumeration is
    # too slow/fragile in this environment, so use the documented defaults.
    $cbConf = "$cbHome\conf\cloudbase-init.conf"
    if (Test-Path $cbConf) { Move-Item $cbConf "$cbConf.orig" -Force }
    Set-Content -Encoding ascii $cbConf @"
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
plugins=cloudbaseinit.plugins.common.mtu.MTUPlugin,
         cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,
         cloudbaseinit.plugins.windows.createuser.CreateUserPlugin,
         cloudbaseinit.plugins.common.setuserpassword.SetUserPasswordPlugin,
         cloudbaseinit.plugins.common.sshpublickeys.SetUserSSHPublicKeysPlugin,
         cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin,
         cloudbaseinit.plugins.windows.winrmlistener.ConfigWinRMListenerPlugin,
         cloudbaseinit.plugins.windows.winrmcertificateauth.ConfigWinRMCertificateAuthPlugin,
         cloudbaseinit.plugins.common.localscripts.LocalScriptsPlugin,
         cloudbaseinit.plugins.common.userdata.UserDataPlugin
metadata_services=cloudbaseinit.metadata.services.nocloudservice.NoCloudConfigDriveService,
                  cloudbaseinit.metadata.services.configdrive.ConfigDriveService

[config_drive]
locations=cdrom
types=iso
"@
    # regenerate sshd host keys on every clone (sysprep /generalize doesn't,
    # and we delete them at seal) via a cloudbase-init LocalScript.
    $ls = "$cbHome\LocalScripts"
    New-Item -ItemType Directory -Force $ls | Out-Null
    Set-Content -Encoding ascii "$ls\00-ssh-hostkeys.ps1" @'
$kc = @("C:\Windows\System32\OpenSSH\ssh-keygen.exe","C:\Program Files\OpenSSH\ssh-keygen.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($kc -and -not (Test-Path "C:\ProgramData\ssh\ssh_host_ed25519_key")) { & $kc -A; Restart-Service sshd -ErrorAction SilentlyContinue }
'@
}

Log '=== actions-runner bundle ==='
$zip = Payload 'actions-runner-win-x64.zip'
if ($zip) {
    if (-not (Get-LocalUser -Name runner -ErrorAction SilentlyContinue)) {
        $pw = ConvertTo-SecureString '4tH2F34cEDRApj8Y@B26' -AsPlainText -Force
        New-LocalUser -Name runner -Password $pw -FullName 'GitHub Runner' -PasswordNeverExpires -ErrorAction SilentlyContinue
    }
    Add-LocalGroupMember -Group Administrators -Member runner -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force 'C:\actions-runner' | Out-Null
    Run 'powershell' @('-NoProfile','-Command',"Expand-Archive '$zip' 'C:\actions-runner' -Force") 480
}

Log '=== eject the provision media ==='
$ej = Payload 'EjectVolumeMedia.exe'
if ($ej) { Run $ej @() 60 }

Log '=== cleanup ==='
Stop-Service sshd -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\ProgramData\ssh\ssh_host_*' -Force -ErrorAction SilentlyContinue
& net.exe user packer /delete 2>$null | Out-Null
netsh advfirewall set allprofiles state on 2>$null | Out-Null
Remove-Item 'C:\provision' -Recurse -Force -ErrorAction SilentlyContinue

Log '=== sysprep + shutdown ==='
Set-Content -Encoding ascii 'C:\Windows\Temp\sysprep-unattend.xml' @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="generalize">
    <component name="Microsoft-Windows-PnpSysprep" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <PersistAllDeviceInstalls>false</PersistAllDeviceInstalls>
    </component>
  </settings>
</unattend>
'@
& "$env:SystemRoot\System32\Sysprep\sysprep.exe" /generalize /oobe /quit /unattend:'C:\Windows\Temp\sysprep-unattend.xml'
Start-Sleep 15
Log '=== power off (kill watchdog, then real shutdown) ==='
try { Stop-Process -Id $watchdog.Id -Force -ErrorAction Stop } catch {}
& shutdown /p /f | Out-Null
