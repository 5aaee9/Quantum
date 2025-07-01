#!/usr/bin/env bash

set -ex

DEBIAN_FRONTEND=noninteractive apt-get install \
  acpid net-tools curl wget vim htop iftop nload mtr lsof \
  localepurge nano iperf3 gnupg2 zip unzip \
  sudo vnstat jq apt-transport-https ca-certificates \
  zsh git parted xfsprogs systemd-cron locales-all \
  tmux build-essential \
  -y

if [ "$(lsb_release -sc)" = "trixie" ]; then
  apt-get install bind9-dnsutils -y
else
  apt-get install dnsutils -y
fi

systemctl enable fstrim.timer
update-initramfs -u -k all

wget -O /usr/local/bin/ffsend "https://glare.root.me/timvisee/ffsend/linux-x64-static"
chmod +x /usr/local/bin/ffsend
