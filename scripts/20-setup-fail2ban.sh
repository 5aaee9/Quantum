#!/usr/bin/env bash

set -ex
apt-get install fail2ban -y

cat > /etc/fail2ban/paths-overrides.local <<EOF
[DEFAULT]
sshd_backend = systemd
EOF
