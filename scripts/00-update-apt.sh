#!/usr/bin/env bash

set -ex

apt-get update -y
apt-get full-upgrade -y
apt-get install lsb-release -y
