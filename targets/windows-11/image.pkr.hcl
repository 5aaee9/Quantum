# Windows 11 Enterprise x64. Build media is generated on Windows by UUP dump.
# Install on SATA; stage VirtIO drivers for deployed virtio-scsi guests.
source "qemu" "windows-11" {
  iso_url           = var.iso_url
  iso_checksum      = var.iso_checksum
  output_directory  = "outputs/windows-11"
  accelerator       = "kvm"
  cpus              = var.numvcpus
  memory            = var.memory
  disk_size         = var.disk_size
  disk_interface    = "ide"
  net_device        = "virtio-net"
  format            = "qcow2"
  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars
  headless          = var.headless
  boot_wait         = "1s"
  boot_command      = ["<up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait><up><wait>"]
  cd_label          = "PROVISION"
  cd_files = [
    "http/windows-11/autounattend.xml",
    "http/windows-11/provision-first-logon.ps1",
    "drivers/windows-11/*",
    "drivers/OpenSSH-Win64.zip",
    "drivers/payloads/CloudbaseInitSetup.msi",
    "drivers/payloads/EjectVolumeMedia.exe",
    "drivers/virtio-win-guest-tools.exe",
  ]
  communicator     = "none"
  shutdown_timeout = "2h"
  qemuargs = [
    ["-machine", "type=q35,accel=kvm"],
    ["-cpu", "host"],
    ["-rtc", "base=localtime,clock=host"],
    ["-vga", "std"],
    ["-device", "qemu-xhci"],
    ["-device", "virtio-tablet"],
    ["-chardev", "socket,id=chrtpm,path=windows-11-tpm.sock"],
    ["-tpmdev", "emulator,id=tpm0,chardev=chrtpm"],
    ["-device", "tpm-tis,tpmdev=tpm0"],
    ["-device", "virtio-serial-pci"],
    ["-chardev", "socket,path=windows-11-qga.sock,server=on,wait=off,id=qga0"],
    ["-device", "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"],
    ["-serial", "file:windows-11-serial.log"],
    ["-monitor", "unix:windows-11-monitor.sock,server,nowait"],
  ]
}
build {
  sources = ["source.qemu.windows-11"]
  post-processor "shell-local" {
    inline = ["bash scripts/check-windows-build.sh windows-11-serial.log"]
  }
}
