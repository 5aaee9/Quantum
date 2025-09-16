#!/usr/bin/env bash

set -ex

dnf install -y \
  net-tools curl wget neovim htop iftop tmux dnsutils \
  nload mtr lsof nano iperf3 gnupg2 zip unzip util-linux-user \
  sudo vnstat jq ca-certificates zsh git parted xfsprogs

systemctl enable fstrim.timer

wget -O /usr/local/bin/ffsend "https://glare.root.me/timvisee/ffsend/linux-x64-static"
chmod +x /usr/local/bin/ffsend
