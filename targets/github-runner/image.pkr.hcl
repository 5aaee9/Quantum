source "qemu" "github-runner" {
  iso_checksum      = "file:https://releases.ubuntu.com/24.04/SHA256SUMS"
  iso_url           = "https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso"

  output_directory  = "outputs/github-runner"
  accelerator       = "kvm"

  cpus              = 4
  memory            = 4096
  disk_size         = "${var.disk_size}"
  disk_interface    = "virtio-scsi"
  format            = "qcow2"

  efi_boot          = true
  efi_firmware_code = "${var.efi_firmware_code}"
  efi_firmware_vars = "${var.efi_firmware_vars}"

  headless          = var.headless
  http_directory    = "http/ubuntu"
  ssh_port          = 22
  ssh_timeout       = "30m"
  ssh_username      = "root"
  ssh_password      = "4tH2F34cEDRApj8Y@B26"
  boot_command      = ["e<down><down><down><end> net.ifnames=0 autoinstall 'ds=nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<F10>"]
  boot_wait         = "${var.boot_wait}"
  qemuargs          = [
    ["-machine", "type=q35,accel=hvf:kvm:whpx:tcg"],
  ]
}

build {
  sources = ["source.qemu.github-runner"]

  provisioner "shell" {
    scripts = [
      "./scripts/debian/00-update-apt.sh",
      "./scripts/debian/10-setup-legacy-bios-support.sh",
      "./scripts/debian/10-setup-apt-packages.sh",
      "./scripts/debian/10-setup-cloud-init.sh",
      "./scripts/generic/20-setup-zsh.sh",
      "./scripts/debian/20-setup-fail2ban.sh",
      "./scripts/generic/30-system-sysctl.sh",
      "./scripts/github-runner/50-setup-github-runner.sh",
      "./scripts/ubuntu/50-platform.sh",
      "./scripts/generic/97-fix-sshd-config.sh",
      "./scripts/debian/98-clean-interfaces.sh",
      "./scripts/debian/98-clear-apt-cache.sh",
      "./scripts/ubuntu/98-clean-default-user.sh",
      "./scripts/generic/99-release-disk-space.sh"
    ]
  }
}
