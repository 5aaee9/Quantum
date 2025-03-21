#!/usr/bin/env bash

set -ex

dnf install grub2-pc -y

parted /dev/vda <<EOF
mkpart linux 34s 2047s
ignore
set 4 bios_grub on
print
quit
EOF

grub2-install --target=i386-pc /dev/vda
