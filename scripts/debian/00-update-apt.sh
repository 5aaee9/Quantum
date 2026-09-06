#!/usr/bin/env bash

set -ex

# Upgrades may otherwise try to ask debconf questions (e.g. a console-setup
# SRU), which fails in this non-tty SSH session and kills the upgrade.
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get full-upgrade -y
apt-get install lsb-release -y

rm -f /etc/apt/sources.list~
