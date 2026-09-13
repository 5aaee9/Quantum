# Windows Server 2025 Datacenter Evaluation + GitHub Actions runner +
# Cloudbase-Init (Windows cloud-init re-implementation).
#
# Boot media layout (qemu):
#   - Windows install ISO          -> first CD-ROM  (D: in WinPE)
#   - cd_files provision ISO       -> second CD-ROM (E: in WinPE)
# The provision ISO carries the virtio-win drivers (needed for the
# virtio-scsi boot disk + virtio-net NIC), autounattend.xml and the
# first-logon bootstrap script. `just build-windows` fetches the drivers
# into ./drivers first.
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
  net_device        = "virtio-net"
  format            = "qcow2"

  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  headless          = var.headless

  # UEFI "Press any key to boot from CD" prompt.
  boot_wait         = var.boot_wait
  boot_command      = ["<space><wait><space><wait><space><wait><space><wait><space><wait><space><wait><space><wait><space><wait><space><wait><space><wait>"]

  # Provision ISO (becomes E: in WinPE — see DriverPaths in autounattend.xml).
  cd_label          = "PROVISION"
  cd_files = [
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
    "http/windows-2025-runner/autounattend.xml",
    "http/windows-2025-runner/provision-first-logon.ps1",
  ]

  # Packer talks to Windows over OpenSSH (installed by the first-logon
  # bootstrap script). Final command: generalize with sysprep and power off;
  # cloudbase-init takes over on first boot of a cloned VM.
  communicator           = "ssh"
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "4h"
  ssh_file_transfer_method = "sftp"
  shutdown_command       = "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Windows/Temp/packer-sysprep-shutdown.ps1"
  shutdown_timeout       = "1h"

  qemuargs = [
    ["-machine", "type=q35,accel=hvf:kvm:whpx:tcg"],
    # Hyper-V enlightenments: large speedup for Windows guests on KVM.
    ["-cpu", "host,hv-passthrough"],
    ["-rtc", "base=localtime,clock=host"],
    ["-vga", "qxl"],
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
