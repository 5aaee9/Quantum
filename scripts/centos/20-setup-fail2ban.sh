#!/usr/bin/env bash

set -ex

dnf install fail2ban -y
systemctl enable fail2ban
