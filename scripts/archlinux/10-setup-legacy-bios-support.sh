#!/usr/bin/env bash

set -ex

pacman -S --noconfirm --needed grub

grub-install --target=i386-pc /dev/vda --recheck
grub-mkconfig -o /boot/grub/grub.cfg
