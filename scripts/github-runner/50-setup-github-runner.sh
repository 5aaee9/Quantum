#!/usr/bin/env bash

set -ex

# Pre-install the latest GitHub Actions self-hosted runner
# (https://github.com/actions/runner) under /opt/actions-runner, owned by
# the unprivileged `runner` user. Registration is left to deploy time,
# because the registration token is short-lived:
#
#   sudo -u runner /opt/actions-runner/config.sh --url https://github.com/<org>/<repo> --token <token>
#   sudo /opt/actions-runner/svc.sh install runner
#   sudo /opt/actions-runner/svc.sh start

RUNNER_DIR=/opt/actions-runner
RUNNER_USER=runner

export DEBIAN_FRONTEND=noninteractive

id -u "$RUNNER_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$RUNNER_USER"
echo "$RUNNER_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$RUNNER_USER"
chmod 440 "/etc/sudoers.d/$RUNNER_USER"

version=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name | ltrimstr("v")')
curl -fsSL -o /tmp/actions-runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${version}/actions-runner-linux-x64-${version}.tar.gz"

mkdir -p "$RUNNER_DIR"
tar -xzf /tmp/actions-runner.tar.gz -C "$RUNNER_DIR"
rm -f /tmp/actions-runner.tar.gz

# Official helper: installs the .NET runtime dependencies (libicu74,
# libkrb5-3, zlib1g, ...) for this distribution.
"$RUNNER_DIR/bin/installdependencies.sh"

chown -R "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_DIR"
