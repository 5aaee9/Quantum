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
  default = "1s"
}

variable "disk_size" {
  type    = string
  default = "81920"
}

variable "numvcpus" {
  type    = number
  default = 4
}

variable "memory" {
  type    = number
  default = 8192
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


# Supplied by scripts/build-windows-11.sh; never silently use a Server ISO.
variable "iso_url" {
  type = string
}
variable "iso_checksum" {
  type = string
}
