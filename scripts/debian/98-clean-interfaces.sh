#!/usr/bin/env bash

cat > /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback
EOF
