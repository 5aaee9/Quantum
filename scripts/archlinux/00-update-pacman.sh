#!/usr/bin/env bash

set -ex

# this fix systemd resolve
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

pacman -Syu --noconfirm
