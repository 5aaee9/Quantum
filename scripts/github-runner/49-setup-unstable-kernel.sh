#!/usr/bin/env bash

set -euxo pipefail

# Install the latest Ubuntu unstable kernel from the Canonical Kernel Team's
# development PPA. These packages are unsupported and may be unstable; this
# image intentionally tracks them for kernel testing on GitHub-hosted runners.
export DEBIAN_FRONTEND=noninteractive

apt-get install --yes software-properties-common
add-apt-repository --yes ppa:canonical-kernel-team/unstable
apt-get update --yes
apt-get install --yes linux-unstable

if grep -qE '^GRUB_DEFAULT=' /etc/default/grub; then
  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
else
  printf '\nGRUB_DEFAULT=0\n' >> /etc/default/grub
fi
update-grub

installed_kernel=$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -n1)
echo "Installed unstable kernel: $installed_kernel"
