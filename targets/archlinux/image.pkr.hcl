source "qemu" "archlinux" {
  iso_checksum      = "file:https://geo.mirror.pkgbuild.com/iso/latest/sha256sums.txt"
  iso_url           = "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso"

  output_directory  = "outputs/archlinux"
  accelerator       = "kvm"

  cpus              = var.numvcpus
  memory            = var.memory
  disk_size         = "${var.disk_size}"
  format            = "qcow2"

  efi_boot          = true
  efi_firmware_code = "${var.efi_firmware_code}"
  efi_firmware_vars = "${var.efi_firmware_vars}"

  headless          = var.headless
  http_directory    = "http/archlinux"
  ssh_port          = 22
  ssh_timeout       = "45m"
  ssh_username      = "root"
  ssh_password      = "4tH2F34cEDRApj8Y@B26"
  boot_command      = [
    "e<end> net.ifnames=0 console=tty0 console=ttyS0,115200<enter><wait30s>",
    "curl http://{{ .HTTPIP }}:{{ .HTTPPort }}/install.sh | bash<enter>"
  ]
  boot_wait         = "${var.boot_wait}"
  qemuargs          = [
    ["-machine", "type=q35,accel=hvf:kvm:whpx:tcg"],
    ["-serial", "file:outputs/archlinux/serial.log"],
  ]
}

build {
  sources = ["source.qemu.archlinux"]

  provisioner "shell" {
    scripts = [
      "./scripts/archlinux/00-update-pacman.sh",
      "./scripts/archlinux/10-setup-legacy-bios-support.sh",
      "./scripts/archlinux/10-setup-pacman-packages.sh",
      "./scripts/archlinux/10-setup-cloud-init.sh",
      "./scripts/generic/20-setup-zsh.sh",
      "./scripts/archlinux/20-setup-fail2ban.sh",
      "./scripts/generic/30-system-sysctl.sh",
      "./scripts/archlinux/50-platform.sh",
      "./scripts/generic/97-fix-sshd-config.sh",
      "./scripts/archlinux/98-clear-pacman-cache.sh",
      "./scripts/generic/98-clear-files.sh",
      "./scripts/generic/99-release-disk-space.sh"
    ]
  }
}
