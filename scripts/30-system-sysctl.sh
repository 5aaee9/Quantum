#!/usr/bin/env bash

set -ex

cat > /etc/sysctl.d/98-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
