#!/usr/bin/env bash

set -ex

apt-get autoremove --purge -y
apt-get clean -y

apt-get purge linux-firmware -y || true

dpkg --list 'linux-image-*' | grep -v $(uname -r) | grep -v meta-package | grep 'linux-image' | grep '^ii' | awk '{print $2}' | xargs apt-get remove --purge -y || true