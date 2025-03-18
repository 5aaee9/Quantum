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

variable "iso_checksum" {
  type    = string
  default = "ee8d8579128977d7dc39d48f43aec5ab06b7f09e1f40a9d98f2a9d149221704a"
}

variable "iso_url" {
  type    = string
  default = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
}

variable "memsize" {
  type    = string
  default = "1024"
}

variable "numvcpus" {
  type    = string
  default = "1"
}

source "qemu" "debian-12" {
  iso_checksum      = "${var.iso_checksum}"
  iso_url           = "${var.iso_url}"

  output_directory  = "outputs/debian12"
  accelerator       = "kvm"

  cpus              = 4
  memory            = 4096
  disk_size         = "${var.disk_size}"

  efi_boot          = true
  efi_firmware_code = "/usr/share/OVMF/OVMF_CODE_4M.fd"
  efi_firmware_vars = "/usr/share/OVMF/OVMF_VARS_4M.fd"

  headless          = false
  http_directory    = "targets/debian-12/http"
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
  sources = ["source.qemu.debian-12"]

  provisioner "shell" {
    scripts = [
      "./scripts/00-update-apt.sh",
      "./scripts/10-setup-apt-packages.sh",
      "./scripts/10-setup-cloud-init.sh",
      "./scripts/98-clear-apt-cache.sh",
      "./scripts/99-release-disk-space.sh"
    ]
  }
}
