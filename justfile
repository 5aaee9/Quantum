set unstable

ci-args := env('CI', '') && "-var-file overrides/headless.pkr.hcl"

build VARIANT:
  sudo packer init targets/{{VARIANT}}
  sudo rm -rf outputs/{{VARIANT}} {{VARIANT}}.qcow2

  sudo packer build {{ci-args}} \
    targets/{{VARIANT}}

  qemu-img convert -O qcow2 -c outputs/{{VARIANT}}/packer-{{VARIANT}} {{VARIANT}}.qcow2

prepare-nixos:
  nix build nixpkgs#OVMFFull.fd
  sudo mkdir -p /usr/share/OVMF
  sudo cp result-fd/FV/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE_4M.fd
  sudo cp result-fd/FV/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS_4M.fd
