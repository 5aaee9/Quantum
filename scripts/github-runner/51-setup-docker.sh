#!/usr/bin/env bash

set -ex

# Docker Engine + Buildx + Compose, the same set the official
# actions/runner-images Ubuntu runners ship with.

export DEBIAN_FRONTEND=noninteractive

. /etc/os-release
CODENAME="$VERSION_CODENAME"

install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $CODENAME stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Keep the daemon healthy on a long-lived cloud VM.
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "local",
  "log-opts": { "max-size": "50m", "max-file": "5" },
  "features": { "buildkit": true }
}
EOF

systemctl enable docker.service containerd.service

# Let the runner user build and run containers without sudo.
usermod -aG docker runner
