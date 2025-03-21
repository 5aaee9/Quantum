#!/usr/bin/env bash

set -ex

dnf install qemu-guest-agent -y

dnf install cloud-utils-growpart cloud-init -y

systemctl add-wants multi-user.target cloud-init.target
