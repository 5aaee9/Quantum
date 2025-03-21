ci-args := env('CI', '') && "-var-file overrides/headless.pkr.hcl"

build VARIANT:
  packer init targets/{{VARIANT}}/image.pkr.hcl
  sudo rm -rf outputs/{{VARIANT}} {{VARIANT}}.qcow2

  sudo packer build {{ci-args}} \
    targets/{{VARIANT}}

  qemu-img convert -O qcow2 -c outputs/{{VARIANT}}/packer-{{VARIANT}} {{VARIANT}}.qcow2
