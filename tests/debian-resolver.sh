#!/usr/bin/env bash
# Run inside a booted Debian image with network connectivity, after cloud-init.
# Read-only checks: do not replace DNS supplied by the guest's network manager.
set -euo pipefail
systemctl is-active --quiet systemd-resolved
test -L /etc/resolv.conf
test "$(readlink -f /etc/resolv.conf)" = /run/systemd/resolve/stub-resolv.conf
grep -Fxq 'FallbackDNS=1.1.1.1' /etc/systemd/resolved.conf.d/10-fallback-dns.conf
# Optionally assert that cloud-init/ifupdown forwarded a supplied DNS server.
if [ -n "${EXPECTED_LINK_DNS:-}" ]; then
  resolvectl dns "${DNS_INTERFACE:-eth0}" | grep -Fq ": $EXPECTED_LINK_DNS"
fi
timeout 20 getent ahostsv4 debian.org
test -n "$(dig +time=5 +tries=1 +short debian.org A)"
resolvectl status
echo 'PASS: resolver service, stub link, fallback configuration and DNS queries'
