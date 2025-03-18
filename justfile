build-debian-12:
  packer init targets/debian-12/image.pkr.hcl
  sudo packer build targets/debian-12/image.pkr.hcl
  qemu-img convert -O qcow2 -c outputs/debian12/packer-debian-12 debian-12.qcow2

build-debian-13:
  packer init targets/debian-13/image.pkr.hcl
  sudo packer build targets/debian-13/image.pkr.hcl
  qemu-img convert -O qcow2 -c outputs/debian13/packer-debian-13 debian-13.qcow2
