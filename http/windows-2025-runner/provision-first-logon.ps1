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
$ErrorActionPreference = 'Stop'

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
    $escaped = $line -replace '([&|<>()^])', '^$1'
    try { & cmd /c "echo PROV: $escaped > COM1" 2>$null | Out-Null } catch {}
    foreach ($tf in 'C:\Windows\Temp\provision.trace','C:\provision.trace') { Add-Content $tf -Value $line -ErrorAction SilentlyContinue }
}

# FirstLogonCommands is the only entry point. A completed build must never
# run provisioning again, nor should a duplicate invocation power it off.
if (Test-Path 'C:\provision-done.marker') { return }

# A hung step eventually powers off, but without BUILD_SUCCESS the host-side
# post-processor rejects the image. Shutdown alone is not a success signal.
$watchdog = Start-Process powershell -PassThru -WindowStyle Hidden `
    -ArgumentList '-NoProfile','-Command','Start-Sleep 5400; shutdown /p /f'
Log 'watchdog armed: poweroff in 90min if provisioning hangs'

try {

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
    throw "Required payload $name not found in $pv"
}

# Retain the native process handle until its exit code has been checked.
# Callers quote arguments containing spaces; an empty argument list is valid.
function Run($exe, [string[]]$argz, [int]$timeoutSec = 600, [int[]]$successCodes = @(0, 3010)) {
    Log "  > $exe $($argz -join ' ')"
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName = $exe
    $proc.StartInfo.Arguments = $argz -join ' '
    $proc.StartInfo.UseShellExecute = $false
    $proc.StartInfo.CreateNoWindow = $true
    try {
        if (-not $proc.Start()) { throw "Could not start $exe" }
        if (-not $proc.WaitForExit($timeoutSec * 1000)) {
            $proc.Kill()
            throw "$exe timed out after ${timeoutSec}s"
        }
        $code = $proc.ExitCode
        Log "  (exit $code)"
        if ($code -notin $successCodes) { throw "$exe failed with exit code $code" }
    } finally {
        $proc.Dispose()
    }
}

Log '=== virtio drivers via pnputil (skip the guest-tools bundle — it hangs) ==='
# the virtio-win-guest-tools MSI wrapper hangs under this environment; just
# pnputil the individual .inf drivers instead (that's all we actually need).
foreach ($inf in (Get-ChildItem "$pv\*.inf" -ErrorAction SilentlyContinue)) {
    # ERROR_NO_MORE_ITEMS (259) means no matching device needs an update.
    # Storage drivers are staged even though this build uses SATA.
    Run 'pnputil' @('/add-driver', $inf.FullName, '/install') 60 @(0, 259, 3010)
}
& pnputil /scan-devices 2>$null | Out-Null

Log '=== OpenSSH (sshd) ==='
$ossh = Payload 'OpenSSH-Win64.zip'
if ($ossh) {
    $sshHome = 'C:\Program Files\OpenSSH'
    Run 'powershell' @('-NoProfile','-Command',"Expand-Archive '$ossh' '$sshHome' -Force") 120
    $nested = Get-ChildItem $sshHome -Directory -Filter 'OpenSSH-Win64' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nested) { Get-ChildItem $nested.FullName | Move-Item -Destination $sshHome -Force }
    Run 'powershell' @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$sshHome\install-sshd.ps1`"") 120
    Set-Service sshd -StartupType Automatic
    Set-Service ssh-agent -StartupType Automatic
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

Log '=== verify installed payloads ==='
foreach ($path in @(
    'C:\Program Files\OpenSSH\sshd.exe',
    'C:\Program Files\Git\bin\git.exe',
    'C:\Program Files\PowerShell\7\pwsh.exe',
    "$cbHome\conf\cloudbase-init.conf",
    'C:\actions-runner\bin\Runner.Listener.exe'
)) {
    if (-not (Test-Path $path)) { throw "Missing installed payload: $path" }
}
Get-Service sshd, cloudbase-init -ErrorAction Stop | Out-Null

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
Run "$env:SystemRoot\System32\Sysprep\sysprep.exe" @('/generalize', '/oobe', '/quit', '/quiet', '/unattend:C:\Windows\Temp\sysprep-unattend.xml') 1200 @(0)
if (-not (Test-Path "$env:SystemRoot\System32\Sysprep\Sysprep_succeeded.tag")) {
    throw 'Sysprep exited without its success tag'
}
New-Item 'C:\provision-done.marker' -ItemType File -Force | Out-Null
Log 'BUILD_SUCCESS'
} catch {
    Log "BUILD_FAILED: $($_.Exception.Message)"
} finally {
    Stop-Process -Id $watchdog.Id -Force -ErrorAction SilentlyContinue
    & shutdown /p /f | Out-Null
}
