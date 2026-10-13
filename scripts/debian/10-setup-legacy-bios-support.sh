#!/usr/bin/env bash

set -ex

# ARM64 boots via UEFI only; there is no i386-pc GRUB target.
if [ "$(dpkg --print-architecture)" = arm64 ]; then
  exit 0
fi

apt-get install grub-pc-bin -y

grub-install --target=i386-pc /dev/sda
