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
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  output_directory = "outputs/windows-2025-runner"
  accelerator      = "kvm"

  cpus      = var.numvcpus
  memory    = var.memory
  disk_size = var.disk_size
  # virtio-scsi (rgl's choice) needs the vioscsi driver inside windowsPE;
  # this Windows build enumerates the disk (partitions it) but never writes
  # a byte — the vioscsi data path never comes up. IDE/SATA needs no driver
  # (in-box storahci) so the install target is guaranteed writable. The
  # provision-ISO drivers still install virtio for the deployed VM.
  disk_interface = "ide"
  # virtio-net — the NIC only matters for boot-time DHCP/diagnostics now
  # (the build is fully offline; packer never connects). virtio matches
  # the disk drivers (virtio-scsi) that ship on the provision ISO.
  net_device = "virtio-net"
  format     = "qcow2"

  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  headless = var.headless

  # UEFI "Press any key to boot from CD or DVD" prompt. The prompt only
  # stays up for a few seconds right after OVMF hands off to bootx64.efi,
  # so the keypresses must land early — unlike the Linux targets (which
  # wait ~10s to reach a grub menu), Windows needs the key during that
  # brief window. boot_wait is intentionally NOT the shared var.boot_wait
  # (10s is already past the prompt); send the Up-arrow train starting
  # ~1s in so several presses straddle the window.
  boot_wait    = "1s"
  boot_command = ["<up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait>"]

  # Single provision ISO at E: (the second CD-ROM): autounattend.xml +
  # the virtio-win drivers + QEMU guest-tools + the first-logon script.
  # Windows Setup scans every CD for autounattend.xml, and DriverPaths in
  # it points at E:\ so Setup injects *all* matching drivers — including
  # NetKVM — into the installed image (this is rgl/windows-vagrant's
  # proven single-CD layout; splitting the answer file onto a floppy left
  # the network driver out and SSH never came up).
  cd_label = "PROVISION"
  cd_files = [
    "http/windows-2025-runner/autounattend.xml",
    "http/windows-2025-runner/provision-first-logon.ps1",
    # the guest has no working TCP under QEMU so the build is fully offline:
    # provision-first-logon.ps1 is self-contained — it installs every payload
    # below, writes cloudbase-init.conf, then syspreps + powers off.
    # every binary payload the orchestrator installs (git, pwsh, cloudbase-init,
    # eject-media, actions-runner) — fetched host-side by
    # scripts/fetch-windows-drivers.sh.
    "drivers/payloads/*",
    # NetKVM 2k22 (not 2k25): the Server-2025 (2k25) NetKVM driver enables
    # NdisPoll by default, and under QEMU that leaves the NIC reporting Up
    # while its datapath moves zero frames — no TX/RX at all. The 2k22
    # driver has no poll mode and binds fine on Server 2025.
    "drivers/NetKVM/2k22/amd64/*.cat",
    "drivers/NetKVM/2k22/amd64/*.inf",
    "drivers/NetKVM/2k22/amd64/*.sys",
    "drivers/NetKVM/2k22/amd64/*.exe",
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

  # Packer does not connect to the guest. Provisioning runs offline from
  # FirstLogonCommands and writes BUILD_SUCCESS only after validation and
  # Sysprep complete. The post-processor checks that record after power-off.
  communicator = "none"
  # Allow installation plus provisioning; the guest watchdog bounds hangs
  # to 90 minutes, without allowing them to pass the success gate.
  shutdown_timeout = "2h"

  qemuargs = [
    # match rgl/windows-vagrant's proven Windows+qemu device set as closely
    # as packer allows (packer owns the disks/ISOs/EFI drives; we only add
    # devices it doesn't generate).
    # q35 supplies the SATA controller used by disk_interface="ide".
    # Local Windows Server 2025 install and shutdown use this machine type.
    ["-machine", "type=q35,accel=kvm:tcg"],
    # Hyper-V enlightenments: large speedup for Windows guests on KVM.
    # plain -cpu host: hv-passthrough exposes Hyper-V enlightenments that
    # make this Server 2025 eval's Setup hang (reads install.wim, partitions
    # the disk, then spins forever issuing zero disk writes). Without it the
    # guest sees a plain KVM host and installs normally.
    ["-cpu", "host"],
    ["-rtc", "base=localtime,clock=host"],
    # std VGA — windowsPE has no qxl driver; std gives a plain VGA console
    # that actually renders the real Setup UI (qxl showed a stale screen
    # hiding the true install state).
    ["-vga", "std"],
    ["-device", "qemu-xhci"],
    ["-device", "virtio-tablet"],
    # attach the boot disk — packer only emits `-drive id=drive0`; the
    # scsi controller + scsi-hd device that maps it into the guest must be
    # added manually (this is exactly rgl/windows-vagrant's pattern).
    # Without these the guest has no disk and installs nowhere.
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
    # No NIC is strictly needed — the build is fully offline (communicator
    # = "none"), so packer's default slirp virtio-net NIC is left in place
    # purely for in-guest diagnostics.
    # NOTE: do NOT add a -drive entry here. A `-drive` in qemuargs makes
    # packer drop *all* of its own generated -drive args (boot disk, the
    # Windows install ISO, the provision CD, and the EFI pflash), so QEMU
    # fails to launch with "can't find value 'drive0'".
  ]
}

build {
  sources = ["source.qemu.windows-2025-runner"]
  # A watchdog/failed provisioner can also power off. Never publish such
  # an image merely because QEMU exited successfully.
  post-processor "shell-local" {
    inline = ["bash scripts/check-windows-build.sh windows-2025-runner-serial.log"]
  }
}
