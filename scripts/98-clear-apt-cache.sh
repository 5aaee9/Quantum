#!/usr/bin/env bash

set -ex

apt-get autoremove --purge -y
apt-get clean -y

find \
  /var/cache/apt \
  /var/lib/apt \
  /var/lib/dhcp \
  /var/log \
  -mindepth 1 -print -delete

rm -vf \
  /etc/adjtime \
  /etc/hostname \
  /etc/hosts \
  /etc/ssh/*key* \
  /var/cache/ldconfig/aux-cache \
  /var/lib/systemd/random-seed \
  ~/.bash_history

truncate -s 0 /etc/machine-id
