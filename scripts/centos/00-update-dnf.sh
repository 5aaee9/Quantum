#!/usr/bin/env bash

set -ex

dnf update -y
dnf install epel-release -y
dnf install lsb-release -y
