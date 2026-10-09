#!/usr/bin/env bash

set -ex

# Install the fallback before systemd-resolved's postinst starts the service.
# Link-specific DNS supplied by DHCP/cloud-init takes precedence over it.
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/10-fallback-dns.conf <<'EOF'
[Resolve]
FallbackDNS=1.1.1.1
EOF

DEBIAN_FRONTEND=noninteractive apt-get install \
  acpid net-tools curl wget neovim htop iftop nload mtr-tiny lsof \
  localepurge nano iperf3 gnupg2 zip unzip \
  sudo vnstat jq apt-transport-https ca-certificates \
  zsh git parted xfsprogs systemd-cron locales-all \
  tmux build-essential systemd-resolved \
  -y

# Bookworm's ifupdown 0.8.41 writes invalid shell assignments and tries to
# execute "DNS" when importing static DNS from cloud-init. Apply the three
# upstream fixes from https://bugs.debian.org/1031236 (fixed in 0.8.42).
# Exact replacements leave already-fixed hooks unchanged.
if [ -f /etc/network/if-up.d/resolved ]; then
  sed -i \
    -e 's/^"\$DNS"=/\$DNS=/' \
    -e 's/^"\$DOMAINS"=/\$DOMAINS=/' \
    -e 's/^\([[:space:]]*\)DNS DNS6 DOMAINS DOMAINS6 DEFAULT_ROUTE$/\1unset DNS DNS6 DOMAINS DOMAINS6 DEFAULT_ROUTE/' \
    /etc/network/if-up.d/resolved
fi

# Route ordinary libc DNS clients through resolved before further downloads.
systemctl enable --now systemd-resolved
systemctl restart systemd-resolved
ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

if [ "$(lsb_release -sc)" = "trixie" ]; then
  apt-get install bind9-dnsutils -y
else
  apt-get install dnsutils -y
fi

systemctl enable fstrim.timer
update-initramfs -u -k all

wget -O /usr/local/bin/ffsend "https://glare.root.me/timvisee/ffsend/linux-x64-static"
chmod +x /usr/local/bin/ffsend
