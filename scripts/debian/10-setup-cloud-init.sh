#!/usr/bin/env bash

set -ex

apt-get install qemu-guest-agent -y
systemctl enable qemu-guest-agent

apt-get install cloud-guest-utils cloud-init -y

systemctl add-wants multi-user.target cloud-init.target

mkdir -p /etc/cloud/cloud.cfg.d

cat > /etc/cloud/cloud.cfg.d/01_debian_cloud.cfg <<EOF
datasource_list:
- NoCloud
- ConfigDrive

apt:
  generate_mirrorlists: true
EOF

cloud-init clean --machine-id
