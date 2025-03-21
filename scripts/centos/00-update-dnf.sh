#!/usr/bin/env bash

set -ex

dnf update -y
dnf install epel-release -y

dnf clean all

dnf install lsb-release -y || dnf install redhat-lsb-core -y
