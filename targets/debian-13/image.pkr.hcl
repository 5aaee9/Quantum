source "qemu" "debian-13" {
  iso_checksum      = "file:https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS"
  iso_url           = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.2.0-amd64-netinst.iso"

  output_directory  = "outputs/debian-13"
  accelerator       = "kvm"

  cpus              = 4
  memory            = 4096
  disk_size         = "${var.disk_size}"
  format            = "qcow2"

  efi_boot          = true
  efi_firmware_code = "${var.efi_firmware_code}"
  efi_firmware_vars = "${var.efi_firmware_vars}"

  headless          = var.headless
  http_directory    = "http/debian"
  ssh_port          = 22
  ssh_timeout       = "30m"
  ssh_username      = "root"
  ssh_password      = "4tH2F34cEDRApj8Y@B26"
  boot_command      = ["e<down><down><down><end>net.ifnames=0 priority=critical auto=true preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<leftCtrlOn>x<leftCtrlOff>"]
  boot_wait         = "${var.boot_wait}"
  qemuargs          = [
    ["-machine", "type=q35,accel=hvf:kvm:whpx:tcg"],
  ]
}

build {
  sources = ["source.qemu.debian-13"]

  provisioner "shell" {
    scripts = [
      "./scripts/debian/00-update-apt.sh",
      "./scripts/debian/10-setup-legacy-bios-support.sh",
      "./scripts/debian/10-setup-apt-packages.sh",
      "./scripts/debian/10-setup-cloud-init.sh",
      "./scripts/generic/20-setup-zsh.sh",
      "./scripts/debian/20-setup-fail2ban.sh",
      "./scripts/generic/30-system-sysctl.sh",
      "./scripts/debian/98-clean-interfaces.sh",
      "./scripts/debian/98-clear-apt-cache.sh",
      "./scripts/generic/99-release-disk-space.sh"
    ]
  }
}
