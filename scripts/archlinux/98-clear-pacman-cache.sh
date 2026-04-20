#!/usr/bin/env bash

set -ex

pacman -Scc --noconfirm || true
pacman -Rns --noconfirm linux-firmware || true
