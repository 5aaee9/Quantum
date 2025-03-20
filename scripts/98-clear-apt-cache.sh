#!/usr/bin/env bash

set -ex

apt-get autoremove --purge -y
apt-get clean -y


for path in /var/cache/apt \
  /var/lib/apt \
  /var/lib/dhcp \
  /var/log; do
  if [ -d $path ]; then
    find $path -mindepth 1 -print -delete
  fi
done

rm -vf \
  /etc/adjtime \
  /etc/hostname \
  /etc/hosts \
  /etc/ssh/*key* \
  /var/cache/ldconfig/aux-cache \
  /var/lib/systemd/random-seed \
  ~/.bash_history

truncate -s 0 /etc/machine-id

rm -f /root/.wget-hsts
