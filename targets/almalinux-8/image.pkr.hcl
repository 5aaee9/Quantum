source "qemu" "almalinux-8" {
  iso_checksum      = "file:https://raw.repo.almalinux.org/almalinux/8/isos/x86_64/CHECKSUM"
  iso_url           = "https://raw.repo.almalinux.org/almalinux/8/isos/x86_64/AlmaLinux-8-latest-x86_64-boot.iso"

  output_directory  = "outputs/almalinux-8"
  accelerator       = "kvm"

  cpus              = var.numvcpus
  memory            = var.memory
  disk_size         = "${var.disk_size}"
  format            = "qcow2"

  efi_boot          = true
  efi_firmware_code = "${var.efi_firmware_code}"
  efi_firmware_vars = "${var.efi_firmware_vars}"

  headless          = var.headless
  http_directory    = "http/almalinux"
  ssh_port          = 22
  ssh_timeout       = "30m"
  ssh_username      = "root"
  ssh_password      = "4tH2F34cEDRApj8Y@B26"
  boot_command      = [
    "<up>e<down><down><end> inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/kickstart-8.cfg<leftCtrlOn>x<leftCtrlOff>"
  ]
  boot_wait         = "${var.boot_wait}"
  qemuargs          = [
    ["-machine", "type=q35,accel=hvf:kvm:whpx:tcg"],
    ["-cpu", "host"],
  ]
}

build {
  sources = ["source.qemu.almalinux-8"]

  provisioner "shell" {
    scripts = [
      "./scripts/centos/00-update-dnf.sh",
      "./scripts/centos/10-setup-dnf-packages.sh",
      "./scripts/centos/10-setup-cloud-init.sh",
      "./scripts/centos/10-setup-legacy-bios.sh",
      "./scripts/centos/20-setup-fail2ban.sh",
      "./scripts/generic/20-setup-zsh.sh",
      "./scripts/generic/30-system-sysctl.sh",
      "./scripts/generic/97-fix-sshd-config.sh",
      "./scripts/generic/98-clear-files.sh",
      "./scripts/centos/99-clear-dnf-cache.sh",
      "./scripts/generic/99-release-disk-space.sh"
    ]
  }
}
