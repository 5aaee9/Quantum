packer {
  required_plugins {
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1"
    }

    vmware = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

variable "boot_wait" {
  type    = string
  default = "5s"
}

variable "disk_size" {
  type    = string
  default = "4096"
}

variable "headless" {
  type    = bool
  default = false
}

variable "efi_firmware_code" {
  type    = string
  default = "/usr/share/OVMF/OVMF_CODE_4M.fd"
}

variable "efi_firmware_vars" {
  type    = string
  default = "/usr/share/OVMF/OVMF_VARS_4M.fd"
}

source "qemu" "debian-13" {
  iso_checksum      = "file:https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/SHA256SUMS"
  iso_url           = "https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/debian-testing-amd64-netinst.iso"

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
      "./scripts/00-update-apt.sh",
      "./scripts/10-setup-apt-packages.sh",
      "./scripts/10-setup-cloud-init.sh",
      "./scripts/20-setup-zsh.sh",
      "./scripts/20-setup-fail2ban.sh",
      "./scripts/30-system-sysctl.sh",
      "./scripts/98-clean-interfaces.sh",
      "./scripts/98-clear-apt-cache.sh",
      "./scripts/99-release-disk-space.sh"
    ]
  }
}
