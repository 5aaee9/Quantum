packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

variable "boot_wait" {
  type    = string
  default = "5s"
}

# Roomy disk: the pre-installed runner bundle and toolchain (runner +
# Docker + Node + Python + CLIs) take ~2 GB, and CI jobs pull container
# images onto the same volume.
variable "disk_size" {
  type    = string
  default = "30720"
}

variable "numvcpus" {
  type    = number
  default = 4
}

variable "memory" {
  type    = number
  default = 4096
}

variable "headless" {
  type    = bool
  default = false
}

variable "efi_firmware_code" {
  type    = string
  default = "/usr/share/AAVMF/AAVMF_CODE.fd"
}

variable "efi_firmware_vars" {
  type    = string
  default = "/usr/share/AAVMF/AAVMF_VARS.fd"
}

# GitHub-hosted ARM64 runners do not expose nested KVM. Local hosts may
# opt into KVM with -var accelerator=kvm -var cpu_model=host.
variable "accelerator" {
  type    = string
  default = "tcg"
}

variable "cpu_model" {
  type    = string
  default = "max"
}
