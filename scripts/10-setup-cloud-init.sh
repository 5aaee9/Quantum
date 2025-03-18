#!/usr/bin/env bash

set -ex

apt-get install qemu-guest-agent -y
systemctl enable qemu-guest-agent

apt-get install cloud-guest-utils cloud-init -y

systemctl add-wants multi-user.target cloud-init.target
