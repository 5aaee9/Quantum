#!/usr/bin/env bash

set -ex

# AlmaLinux mirrors can briefly expose newer AppStream packages before their
# matching BaseOS dependencies. Keep the best installable update set so image
# builds continue during repository synchronization.
dnf update --nobest -y
dnf install epel-release -y

dnf clean all

dnf install lsb-release -y || dnf install redhat-lsb-core -y
