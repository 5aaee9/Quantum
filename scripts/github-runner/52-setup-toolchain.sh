#!/usr/bin/env bash

set -ex

# Lightweight CI toolchain: the high-frequency subset of the official
# actions/runner-images toolset (including latest Rust stable via rustup).
# Deliberately excluded for size: Android SDK/NDK, browsers + Selenium,
# multi-version Java/Go/.NET, and the AWS/Azure/GCP CLIs - actions like
# setup-java/setup-go cover those.

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

# --- Rust (latest stable via rustup) -----------------------------------------
RUNNER_USER=runner
RUNNER_HOME=$(getent passwd "$RUNNER_USER" | cut -d: -f6)
RUSTUP_HOME="${RUNNER_HOME}/.rustup"
CARGO_HOME="${RUNNER_HOME}/.cargo"

sudo -u "$RUNNER_USER" -H env \
  HOME="$RUNNER_HOME" \
  RUSTUP_HOME="$RUSTUP_HOME" \
  CARGO_HOME="$CARGO_HOME" \
  bash -c 'curl --proto "=https" --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile default --default-toolchain stable'

for bin in rustup cargo rustc rustdoc rustfmt cargo-fmt cargo-clippy clippy-driver; do
  if [ -x "${CARGO_HOME}/bin/${bin}" ]; then
    ln -sf "${CARGO_HOME}/bin/${bin}" "/usr/local/bin/${bin}"
  fi
done

cat > /etc/profile.d/rust.sh <<'EOF'
if [ -d "${HOME}/.cargo/bin" ]; then
  case ":${PATH}:" in
    *":${HOME}/.cargo/bin:"*) ;;
    *) export PATH="${HOME}/.cargo/bin:${PATH}" ;;
  esac
fi
EOF
chmod 0644 /etc/profile.d/rust.sh

sudo -u "$RUNNER_USER" -H env \
  HOME="$RUNNER_HOME" \
  RUSTUP_HOME="$RUSTUP_HOME" \
  CARGO_HOME="$CARGO_HOME" \
  PATH="${CARGO_HOME}/bin:${PATH}" \
  bash -c 'rustc --version && cargo --version && rustfmt --version && cargo clippy --version'
