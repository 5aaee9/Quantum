# Windows Server 2025 Datacenter Evaluation + GitHub Actions runner +
# Cloudbase-Init (Windows cloud-init re-implementation).
#
# Boot media layout (qemu):
#   - Windows install ISO    -> first CD-ROM  (D: in WinPE)
#   - cd_files provision ISO -> second CD-ROM (E: in WinPE)
# The provision ISO carries autounattend.xml, the virtio-win drivers
# (virtio-scsi boot disk + virtio-net NIC + friends), the QEMU
# guest-tools installer, and the first-logon bootstrap script.
# `just build-windows` fetches the drivers into ./drivers first.
#
# Structure follows rgl/windows-vagrant (proven packer+qemu windows
# builds): https://github.com/rgl/windows-vagrant

source "qemu" "windows-2025-runner" {
  iso_url           = var.iso_url
  iso_checksum      = var.iso_checksum

  output_directory  = "outputs/windows-2025-runner"
  accelerator       = "kvm"

  cpus              = var.numvcpus
  memory            = var.memory
  disk_size         = var.disk_size
  disk_interface    = "virtio-scsi"
  # virtio-net — NetKVM is the well-supported virtio NIC driver on QEMU
  # and is what rgl/windows-vagrant uses. (e1000 bound as 'Intel PRO/1000'
  # but even a forced static address couldn't reach slirp — its Windows
  # driver doesn't reliably TX on QEMU's e1000 emulation.)
  net_device        = "virtio-net"
  format            = "qcow2"

  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  headless          = var.headless

  # UEFI "Press any key to boot from CD or DVD" prompt. The prompt only
  # stays up for a few seconds right after OVMF hands off to bootx64.efi,
  # so the keypresses must land early — unlike the Linux targets (which
  # wait ~10s to reach a grub menu), Windows needs the key during that
  # brief window. boot_wait is intentionally NOT the shared var.boot_wait
  # (10s is already past the prompt); send the Up-arrow train starting
  # ~1s in so several presses straddle the window.
  boot_wait         = "1s"
  boot_command      = ["<up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait>"]

  # Single provision ISO at E: (the second CD-ROM): autounattend.xml +
  # the virtio-win drivers + QEMU guest-tools + the first-logon script.
  # Windows Setup scans every CD for autounattend.xml, and DriverPaths in
  # it points at E:\ so Setup injects *all* matching drivers — including
  # NetKVM — into the installed image (this is rgl/windows-vagrant's
  # proven single-CD layout; splitting the answer file onto a floppy left
  # the network driver out and SSH never came up).
  cd_label          = "PROVISION"
  cd_files = [
    "http/windows-2025-runner/autounattend.xml",
    "http/windows-2025-runner/provision-first-logon.ps1",
    "drivers/NetKVM/2k25/amd64/*.cat",
    "drivers/NetKVM/2k25/amd64/*.inf",
    "drivers/NetKVM/2k25/amd64/*.sys",
    "drivers/NetKVM/2k25/amd64/*.exe",
    "drivers/vioscsi/2k25/amd64/*.cat",
    "drivers/vioscsi/2k25/amd64/*.inf",
    "drivers/vioscsi/2k25/amd64/*.sys",
    "drivers/vioserial/2k25/amd64/*.cat",
    "drivers/vioserial/2k25/amd64/*.inf",
    "drivers/vioserial/2k25/amd64/*.sys",
    "drivers/viostor/2k25/amd64/*.cat",
    "drivers/viostor/2k25/amd64/*.inf",
    "drivers/viostor/2k25/amd64/*.sys",
    "drivers/virtio-win-guest-tools.exe",
    # OpenSSH rides on the ISO — the guest can't reach the internet through
    # QEMU/slirp (ICMP to the gateway works but TCP never establishes), so
    # the first-logon script extracts it from the CD rather than download.
    "drivers/OpenSSH-Win64.zip",
  ]

  # Packer talks to Windows over OpenSSH (installed by the first-logon
  # bootstrap script). Final command: generalize with sysprep and power off;
  # cloudbase-init takes over on first boot of a cloned VM.
  communicator           = "ssh"
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  # SSH straight to the guest's tap-NIC address, NOT via slirp hostfwd.
  # QEMU user-mode (slirp) cannot carry TCP for this Windows guest at all
  # — ICMP to the gateway works but no TCP connection (inbound hostfwd OR
  # outbound) ever establishes, a known slirp<->Windows quirk. The build
  # therefore attaches a real TAP device (created by the workflow Build
  # step, NAT'd to the runner's eth0) on which the guest has a normal,
  # fully-working TCP/IP stack. ssh_host/ssh_port make packer dial the tap
  # address directly instead of the forwarded localhost port.
  ssh_host               = "10.0.3.15"
  ssh_port               = 22
  # 90min is generous — sshd comes up within a few minutes of the desktop
  # appearing; a longer wait just delays discovering a broken bootstrap.
  ssh_timeout            = "90m"
  ssh_file_transfer_method = "sftp"
  shutdown_command       = "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Windows/Temp/packer-sysprep-shutdown.ps1"
  shutdown_timeout       = "1h"

  qemuargs = [
    # match rgl/windows-vagrant's proven Windows+qemu device set as closely
    # as packer allows (packer owns the disks/ISOs/EFI drives; we only add
    # devices it doesn't generate).
    ["-machine", "type=q35,accel=kvm:tcg,hpet=off"],
    # Hyper-V enlightenments: large speedup for Windows guests on KVM.
    ["-cpu", "host,hv-passthrough"],
    ["-rtc", "base=localtime,clock=host"],
    ["-vga", "qxl"],
    ["-device", "qemu-xhci"],
    ["-device", "virtio-tablet"],
    # virtio serial console + QEMU guest-agent channel (rgl has these).
    ["-device", "virtio-serial-pci"],
    ["-chardev", "socket,path=windows-2025-runner-qga.sock,server=on,wait=off,id=qga0"],
    ["-device", "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"],
    # Capture the guest serial console (OVMF boot log lands here) and a
    # QEMU monitor socket so the Build step can grab a screendump of the
    # guest's display on failure — shows exactly which screen it's stuck
    # on (OOBE prompt, login, error dialog, etc).
    ["-serial", "file:windows-2025-runner-serial.log"],
    ["-monitor", "unix:windows-2025-runner-monitor.sock,server,nowait"],
    # Real TAP network — slirp can't carry TCP for this guest (see
    # ssh_host note). The workflow Build step pre-creates tap0
    # (10.0.3.1/24, NAT'd to eth0); the guest gets 10.0.3.15 statically.
    # MAC 52:54:00:aa:bb:cc marks this NIC so the first-logon script can
    # pick it out from packer's own (slirp, non-functional) NIC.
    ["-netdev", "tap,id=tap0,ifname=tap0,script=no,downscript=no"],
    ["-device", "virtio-net-pci,netdev=tap0,mac=52:54:00:aa:bb:cc"],
    # NOTE: do NOT add a -drive entry here. A `-drive` in qemuargs makes
    # packer drop *all* of its own generated -drive args (boot disk, the
    # Windows install ISO, the provision CD, and the EFI pflash), so QEMU
    # fails to launch with "can't find value 'drive0'". Diagnostics go to
    # the host over slirp's 10.0.2.2:8080 listener instead.
  ]
}

build {
  sources = ["source.qemu.windows-2025-runner"]

  provisioner "powershell" {
    script = "./scripts/windows/10-setup-guest-tools.ps1"
  }

  provisioner "windows-restart" {
  }

  provisioner "powershell" {
    scripts = [
      "./scripts/windows/20-setup-git.ps1",
      "./scripts/windows/21-setup-pwsh.ps1",
      "./scripts/github-runner/50-setup-runner-win.ps1",
      "./scripts/windows/30-setup-cloudbase-init.ps1",
      "./scripts/windows/90-eject-media.ps1",
    ]
  }

  # Last provisioner: uploads the sysprep shutdown script invoked by
  # shutdown_command, removes ssh host keys and the packer build account.
  provisioner "powershell" {
    script = "./scripts/windows/99-cleanup.ps1"
  }
}
