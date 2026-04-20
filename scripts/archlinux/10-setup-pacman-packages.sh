#!/usr/bin/env bash

set -ex

pacman -S --noconfirm --needed \
  acpid net-tools curl wget neovim htop iftop nload mtr lsof \
  nano iperf3 gnupg zip unzip sudo vnstat jq ca-certificates \
  zsh git parted xfsprogs tmux base-devel bind

systemctl enable fstrim.timer

wget -O /usr/local/bin/ffsend "https://glare.root.me/timvisee/ffsend/linux-x64-static"
chmod +x /usr/local/bin/ffsend
