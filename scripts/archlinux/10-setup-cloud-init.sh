#!/usr/bin/env bash

set -ex

pacman -S --noconfirm --needed qemu-guest-agent cloud-init cloud-guest-utils

systemctl enable qemu-guest-agent
systemctl add-wants multi-user.target cloud-init.target

mkdir -p /etc/cloud/cloud.cfg.d

cat > /etc/cloud/cloud.cfg.d/01_archlinux_cloud.cfg <<'CLOUDCFG'
datasource_list:
- NoCloud
- ConfigDrive
CLOUDCFG

cloud-init clean --machine-id || cloud-init clean
