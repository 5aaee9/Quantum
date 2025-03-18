build-debian-12:
    packer init targets/debian-12/image.pkr.hcl
    sudo packer build targets/debian-12/image.pkr.hcl