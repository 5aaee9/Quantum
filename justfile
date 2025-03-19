build VARIANT:
  packer init targets/{{VARIANT}}/image.pkr.hcl
  sudo rm -rf outputs/{{VARIANT}} {{VARIANT}}.qcow2
  sudo packer build targets/{{VARIANT}}/image.pkr.hcl
  qemu-img convert -O qcow2 -c outputs/{{VARIANT}}/packer-{{VARIANT}} {{VARIANT}}.qcow2
