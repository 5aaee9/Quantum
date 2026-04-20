#!/usr/bin/env bash

set -ex

pacman -S --noconfirm --needed fail2ban
systemctl enable fail2ban
