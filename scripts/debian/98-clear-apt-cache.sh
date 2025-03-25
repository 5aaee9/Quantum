#!/usr/bin/env bash

set -ex

apt-get autoremove --purge -y
apt-get clean -y

apt-get purge linux-firmware -y
