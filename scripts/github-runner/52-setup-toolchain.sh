#!/usr/bin/env bash

set -ex

# Lightweight CI toolchain: the high-frequency subset of the official
# actions/runner-images toolset. Deliberately excluded for size: Android
# SDK/NDK, browsers + Selenium, multi-version Java/Go/Rust/.NET, and the
# AWS/Azure/GCP CLIs - actions like setup-java/setup-go cover those.

export DEBIAN_FRONTEND=noninteractive

install -m 0755 -d /etc/apt/keyrings

# --- Node.js 22 LTS (NodeSource) + yarn ------------------------------------
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
npm install -g yarn

# --- Python tooling (Ubuntu noble ships 3.12) -------------------------------
apt-get install -y python3-pip python3-venv python3-full python3-dev

# --- GitHub CLI --------------------------------------------------------------
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list

# --- Terraform (HashiCorp apt repo) ------------------------------------------
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/hashicorp.list

apt-get update -y
apt-get install -y gh terraform

# --- Misc small utilities ----------------------------------------------------
apt-get install -y git-lfs postgresql-client default-mysql-client

# --- kubectl + helm: latest static binaries (no stale apt channel pin) -------
kubectl_version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSL -o /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# get.helm.sh/helm-latest-version returns e.g. "v4.2.4" (leading v included)
helm_version=$(curl -fsSL https://get.helm.sh/helm-latest-version | tr -d '"')
curl -fsSL -o /tmp/helm.tar.gz \
  "https://get.helm.sh/helm-${helm_version}-linux-amd64.tar.gz"
tar -xzf /tmp/helm.tar.gz -C /tmp
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
rm -rf /tmp/helm.tar.gz /tmp/linux-amd64
