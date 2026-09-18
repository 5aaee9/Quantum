# Runs from FirstLogonCommands (autounattend.xml), elevated as the local
# `packer` user via the provision floppy. Brings up OpenSSH so packer can
# take over the rest of the provisioning. Everything is logged because
# there is no interactive user to watch the console.
#
# Mirrors rgl/windows-vagrant provision-openssh.ps1 (proven on QEMU/KVM):
# https://github.com/rgl/windows-vagrant
# Write a marker to COM1 as the *very first* statement — before anything
# that can fail — so the serial log proves the script actually ran. QEMU
# captures COM1 to windows-2025-runner-serial.log.
$script:com1 = $null
foreach ($m in 'file','serialport') {
    try {
        if ($m -eq 'file') {
            $script:com1 = [System.IO.File]::OpenWrite('\\.\COM1')
        } else {
            $script:com1 = New-Object System.IO.Ports.SerialPort COM1
            $script:com1.Open()
        }
        if ($script:com1) { break }
    } catch { $script:com1 = $null }
}
function Write-Com1($msg) {
    Write-Host $msg
    if (-not $script:com1) { return }
    try {
        $line = "[first-logon] $msg`r`n"
        if ($script:com1 -is [System.IO.FileStream]) {
            $b = [Text.Encoding]::ASCII.GetBytes($line)
            $script:com1.Write($b, 0, $b.Length); $script:com1.Flush()
        } else {
            $script:com1.WriteLine("[first-logon] $msg")
        }
    } catch {}
}

# report a line to the host via slirp's 10.0.2.2 gateway: the CI runner
# listens on :8080 and logs every request. Works even when COM1/A: don't.
function Write-Status($text) {
    Write-Com1 $text
    try { Add-Content -Path 'A:\STATUS.TXT' -Value $text -ErrorAction Stop } catch {}
    try {
        $q = [uri]::EscapeDataString($text)
        Invoke-WebRequest -Uri "http://10.0.2.2:8080/?s=$q" -UseBasicParsing -TimeoutSec 5 | Out-Null
    } catch {}
}
Write-Com1 'bootstrap starting'

# --- NIC self-heal ---------------------------------------------------------
# If no adapter has an IPv4 address the virtio NetKVM driver never bound;
# force-install every driver .inf on the provision CD so the NIC comes up
# before we do anything network-dependent. Runs elevated (UAC is off).
try {
    # Heal when the NIC isn't actually usable: no non-APIPA IPv4, OR a PNP
    # net device still in Error. 'Status -eq Up' is NOT enough — a virtio
    # NIC with no NetKVM still reports link-Up and grabs a 169.254.x APIPA
    # address, which made the old -not-$up check skip the heal entirely.
    $hasRealIp = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' }
    $erroredNic = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Error' }
    if (-not $hasRealIp -or $erroredNic) {
        Write-Status ("nic-heal realIp=" + [bool]$hasRealIp + " err=" + (($erroredNic | ForEach-Object FriendlyName) -join ';'))
        # install the full virtio guest-tools — it registers AND binds
        # NetKVM/vioscsi on already-enumerated devices (pnputil only stages
        # into the driver store; the NIC can stay driverless until rescan).
        foreach ($d in 'D','E','F','G','H') {
            $gt = "${d}:\virtio-win-guest-tools.exe"
            if (Test-Path $gt) { Write-Status 'gt-install'; Start-Process $gt -ArgumentList '/install','/quiet','/norestart' -Wait }
        }
        # fall back to staging every driver .inf on the provision CD.
        foreach ($d in 'D','E','F','G','H') {
            if (Test-Path "${d}:\*.inf") { & pnputil /add-driver "${d}:\*.inf" /subdirs /install 2>$null | Out-Null }
        }
        # rescan so the freshly-registered NetKVM binds to the
        # already-present 'Ethernet Controller' devices.
        & pnputil /scan-devices 2>$null | Out-Null
        Start-Sleep -Seconds 12
    }
    # The NIC may be bound but sitting on APIPA because its first DHCP
    # Discover raced the driver bind. Release+renew a few times until slirp
    # hands it 10.0.2.15 (bounce the adapter first to force a clean cycle).
    $tries = 0
    while ($tries -lt 6) {
        $hasRealIp = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' }
        if ($hasRealIp) { break }
        Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
            try { Disable-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction Stop } catch {}
            try { Enable-NetAdapter  -Name $_.Name -Confirm:$false -ErrorAction Stop } catch {}
            try { & ipconfig /release $_.Name 2>$null | Out-Null } catch {}
            try { & ipconfig /renew   $_.Name 2>$null | Out-Null } catch {}
        }
        $tries++
        Start-Sleep -Seconds 10
    }
    # Last resort: QEMU user networking is a fixed 10.0.2.0/24 (gw .2, dns
    # .3, guest .15). If DHCP never answered, just set it statically — this
    # is a build VM, the address is deterministic.
    $hasRealIp = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' }
    if (-not $hasRealIp) {
        Write-Status 'dhcp-failed setting static 10.0.2.15'
        Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
            $n = $_.Name
            # netsh is the reliable way to force a static address —
            # New-NetIPAddress silently no-ops when the interface still has
            # an APIPA lease / DHCP enabled.
            try { & netsh interface ip set address name="$n" static 10.0.2.15 255.255.255.0 10.0.2.2 2>$null | Out-Null } catch {}
            try { & netsh interface ip set dns    name="$n" static 10.0.2.3 2>$null | Out-Null } catch {}
            try { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses 10.0.2.3 -ErrorAction SilentlyContinue } catch {}
            try {
                New-NetIPAddress -InterfaceIndex $_.ifIndex -IPAddress 10.0.2.15 -PrefixLength 24 -DefaultGateway 10.0.2.2 -ErrorAction Stop | Out-Null
            } catch {}
        }
        Start-Sleep -Seconds 5
    }
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254*' } | Select-Object -First 1).IPAddress
    Write-Status ("SCRIPT-STARTED adapters=" + ((Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { $_.Name + ':' + $_.Status }) -join ',') + " ip=$ip")
    # also paint the network state on the console so a VNC/monitor
    # screendump shows it even when outbound pings can't reach the host.
    Write-Host '==================== NETSTATE ===================='
    Get-NetAdapter -ErrorAction SilentlyContinue | Format-Table Name,Status,InterfaceDescription -Auto | Out-String | Write-Host
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Format-Table InterfaceAlias,IPAddress -Auto | Out-String | Write-Host
    Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Format-Table ifIndex,NextHop -Auto | Out-String | Write-Host
    Get-PnpDevice -Class Net -ErrorAction SilentlyContinue | Format-Table Status,FriendlyName -Auto | Out-String | Write-Host
    # can the guest reach slirp at all? a reachable 10.0.2.2 means the NIC
    # dataplane works and only DHCP/sshd is missing; unreachable means the
    # virtio-net device isn't actually exchanging frames with user.0.
    $ping = Test-Connection -ComputerName 10.0.2.2 -Count 2 -Quiet -ErrorAction SilentlyContinue
    Write-Host ("PING 10.0.2.2 = " + $ping)
    try { $tnc = (Test-NetConnection -ComputerName 10.0.2.2 -Port 8080 -WarningAction SilentlyContinue).TcpTestSucceeded } catch { $tnc = $false }
    Write-Host ("TCP 10.0.2.2:8080 = " + $tnc)
    Write-Host '=================================================='
    # hold the NETSTATE block on screen for ~90s so a screendump catches it
    # before the (network-bound) OpenSSH download step runs.
    Start-Sleep -Seconds 90
} catch { Write-Status ("SCRIPT-STARTED netcheck-err " + $_.Exception.Message) }

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

Start-Transcript -Path 'C:\Windows\Temp\first-logon.log' -Append | Out-Null

trap {
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$', 'ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$', 'ERROR EXCEPTION: $1' | Write-Host
    Write-Status ("TRAP ERROR: " + $_.Exception.Message)
    Write-Status ("TRAP AT: " + $_.InvocationInfo.PositionMessage)
    Write-Status 'STATUS: failed'
    try {
        Add-Content -Path 'A:\STATUS.TXT' -Value "TRAP ERROR: $($_.Exception.Message)"
        Add-Content -Path 'A:\STATUS.TXT' -Value "TRAP AT: $($_.InvocationInfo.PositionMessage)"
        Add-Content -Path 'A:\STATUS.TXT' -Value 'STATUS: failed'
    } catch {}
    Stop-Transcript | Out-Null
    # leave the VM up for a while so a failed run can be inspected over VNC.
    Start-Sleep -Seconds (60*60)
    Exit 1
}

[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# --- network profile -------------------------------------------------------
# QEMU user-net (slirp) delivers packer's inbound connection through the NAT
# gateway. On a *Public* profile Windows applies stealth-mode inbound drops
# below the firewall-rule layer, which is exactly the "TCP connects but the
# SSH banner never arrives" failure. Mark every interface Private and open
# the port before touching sshd.
Get-NetConnectionProfile `
    | Where-Object { $_.NetworkCategory -ne 'DomainAuthenticated' } `
    | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
if (-not (Get-NetFirewallRule -DisplayName 'SSH' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'SSH' -Direction Inbound -Protocol TCP `
        -LocalPort 22 -Action Allow -Profile Any | Out-Null
}

# --- OpenSSH -------------------------------------------------------------
# Install the PowerShell/Win32-OpenSSH release. Binaries land in
# $openSshHome; config, host keys and logs in $openSshConfigHome.
$openSshHome = 'C:\Program Files\OpenSSH'
$openSshConfigHome = 'C:\ProgramData\ssh'

Add-Type -AssemblyName System.IO.Compression.FileSystem

# uninstall the Windows provided OpenSSH binaries.
Write-Status 'STEP: enumerate-openssh-capabilities'
$windowsOpenSshCapabilities = Get-WindowsCapability -Online -Name 'OpenSSH.*' | Where-Object { $_.State -ne 'NotPresent' }
if ($windowsOpenSshCapabilities) {
    Write-Status 'STEP: removing-windows-openssh'
    $windowsOpenSshCapabilities | Remove-WindowsCapability -Online | Out-Null
}

Write-Status 'STEP: download-openssh-zip'
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
        Write-Com1 "openssh download failed, retrying..."
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

Write-Com1 'Setting the host file permissions...'
&"$openSshHome\FixHostFilePermissions.ps1" -Confirm:$false

Write-Com1 'Configuring sshd and ssh-agent services...'
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

Write-Status 'STEP: start-sshd'
Write-Com1 'Starting the sshd service...'
Start-Service sshd
Write-Status 'STEP: sshd-started'

Write-Com1 'Firewall rule added; sshd up'
New-NetFirewallRule -Protocol TCP -LocalPort 22 -Direction Inbound -Action Allow -DisplayName SSH | Out-Null

# --- stop the autologon ---------------------------------------------------
# LogonCount=1 in autounattend.xml already expires after this session; also
# clear the flag and any stored default credentials.
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $winlogon -Name AutoAdminLogon -Value 0
'AutoLogonCount', 'DefaultUserName', 'DefaultPassword' | ForEach-Object {
    Remove-ItemProperty -Path $winlogon -Name $_ -ErrorAction SilentlyContinue
}

Write-Com1 'First-logon bootstrap complete; sshd is listening.'

# dump diagnostics to the serial log AND to the host over slirp's
# always-present 10.0.2.2 gateway — the CI runner listens on :8080 and
# logs every request, a channel that works regardless of whether A:/COM1
# are wired up. A failed SSH connect can then be diagnosed from CI output.
function Write-Status($text) {
    Write-Com1 $text
    try { Add-Content -Path 'A:\STATUS.TXT' -Value $text -ErrorAction Stop } catch {}
    try {
        $q = [uri]::EscapeDataString($text)
        Invoke-WebRequest -Uri "http://10.0.2.2:8080/?s=$q" -UseBasicParsing -TimeoutSec 5 | Out-Null
    } catch {}
}
try {
    Write-Status ("NET: " + ((Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.InterfaceAlias + '=' + $_.IPAddress }) -join ', '))
    Write-Status ("PROFILE: " + ((Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object { $_.InterfaceAlias + '=' + $_.NetworkCategory }) -join ', '))
    Write-Status ("DEFGW: " + ((Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object { $_.NextHop }) -join ', '))
    Write-Status ("SSHD: " + (Get-Service sshd -ErrorAction SilentlyContinue).Status)
    Write-Status ("LISTEN22: " + ((Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue).Count))
    Write-Status ("LISTEN22addr: " + ((Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { $_.LocalAddress }) -join ','))
    Write-Status ("FW: " + ((Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object { $_.Name + '=' + $_.Enabled }) -join ', '))
    Write-Status ("DNS-test: " + ((Test-NetConnection -ComputerName github.com -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded))
    Write-Status 'STATUS: complete'
} catch { Write-Status "diag failed: $_" }

Stop-Transcript | Out-Null
logoff
