source "qemu" "github-runner-arm64" {
  # Official Ubuntu 24.04 ARM64 cloud disk; provision the same software as
  # the amd64 ISO target without a slow interactive installer under TCG.
  iso_checksum     = "file:https://cloud-images.ubuntu.com/noble/current/SHA256SUMS"
  iso_url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img"
  disk_image       = true
  output_directory = "outputs/github-runner-arm64"
  qemu_binary      = "qemu-system-aarch64"
  machine_type     = "virt"
  accelerator      = var.accelerator
  cpus             = var.numvcpus
  memory           = var.memory
  disk_size        = var.disk_size
  disk_interface   = "virtio-scsi"
  net_device       = "virtio-net-pci"
  format           = "qcow2"

  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  headless         = var.headless
  cd_files         = ["http/github-runner-arm64/user-data", "http/github-runner-arm64/meta-data"]
  cd_label         = "cidata"
  cdrom_interface  = "virtio-scsi"
  ssh_username     = "root"
  ssh_password     = "4tH2F34cEDRApj8Y@B26"
  ssh_timeout      = "30m"
  boot_wait        = var.boot_wait
  boot_command     = []
  shutdown_command = "shutdown -P now"
  shutdown_timeout = "5m"
  qemuargs = [
    ["-cpu", var.cpu_model],
    ["-serial", "file:github-runner-arm64-serial.log"],
  ]
}

build {
  sources = ["source.qemu.github-runner-arm64"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait",
      "DEBIAN_FRONTEND=noninteractive apt-get purge -y snapd",
    ]
  }

  provisioner "shell" {
    scripts = split("\n", trimspace(file("../../scripts/github-runner/provisioners.txt")))
  }

  # Execute the installed ARM binaries in the actual guest, not on the host.
  provisioner "shell" {
    script = "tests/github-runner-smoke.sh"
  }
}
