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
  default = "61440"
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

# Windows Server 2025 Evaluation ISO (en-US, refreshed 2026-01).
# The Evaluation Center does not publish permanent links. When this goes
# stale either:
#   - run `bash scripts/update-windows-iso.sh` (follows the
#     rgl/windows-evaluation-isos-scraper feed), or
#   - mirror the ISO to alist and set WINDOWS_2025_ISO_URL to the alist
#     link, e.g. https://alist.indexyz.me/d/Local/Isos/windows-server-2025-eval.iso
# Can always be overridden with -var / PKR_VAR_* / the env vars below.
variable "iso_url" {
  type = string
  default = env("WINDOWS_2025_ISO_URL") != "" ? env("WINDOWS_2025_ISO_URL") : "https://software-static.download.prss.microsoft.com/dbazure/998969d5-f34g-4e03-ac9d-1f9786c66749/26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
}

variable "iso_checksum" {
  type = string
  default = env("WINDOWS_2025_ISO_CHECKSUM") != "" ? env("WINDOWS_2025_ISO_CHECKSUM") : "sha256:7b052573ba7894c9924e3e87ba732ccd354d18cb75a883efa9b900ea125bfd51"
}

# NB the WIM index is hardcoded in http/windows-2025-runner/autounattend.xml
#    (cd_files cannot template): 4 = Datacenter Eval (Desktop Experience),
#    3 = Datacenter Eval (Server Core).

# Temporary local administrator created by autounattend.xml; packer uses it
# over SSH. Removed before sysprep.
variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "ssh_password" {
  type    = string
  default = "4tH2F34cEDRApj8Y@B26"
}
