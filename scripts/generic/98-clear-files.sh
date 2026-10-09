#!/usr/bin/env bash

set -ex

for path in /var/cache/apt \
  /var/lib/apt \
  /var/lib/dhcp \
  /var/log \
  /etc/NetworkManager/system-connections \
  /etc/netplan; do
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
  ~/.bash_history \
  ~/.wget-hsts \
  /root/original-ks.cfg \
  /root/anaconda-ks.cfg \
  /root/.wget-hsts

# Drop build-time DNS addresses, but retain runtime resolver links, including
# dangling links whose /run target will be recreated on the next boot.
if [ ! -L /etc/resolv.conf ]; then
  rm -vf /etc/resolv.conf
fi

truncate -s 0 /etc/machine-id
