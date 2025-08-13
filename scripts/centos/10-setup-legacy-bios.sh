#!/usr/bin/env bash

set -ex

dnf install grub2-pc -y
grub2-install --target=i386-pc /dev/vda
grub2-mkconfig -o /boot/grub2/grub.cfg
