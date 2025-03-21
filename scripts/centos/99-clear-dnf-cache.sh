#!/usr/bin/env bash

set -ex

dnf clean all
dnf remove linux-firmware -y
