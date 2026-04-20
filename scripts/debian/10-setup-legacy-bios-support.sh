#!/usr/bin/env bash

set -ex

apt-get install grub-pc-bin -y

grub-install --target=i386-pc /dev/sda
