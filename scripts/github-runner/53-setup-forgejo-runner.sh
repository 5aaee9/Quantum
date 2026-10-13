#!/usr/bin/env bash

set -ex

# Pre-install the official forgejo-runner binary so Shaula's Forgejo VM
# bootstrap can skip the download. Pinned to the same version + SHA-256 that
# Shaula's bootstrap verifies; Shaula re-checks the hash at boot and falls
# back to downloading on mismatch, so bump both together.
#
# Nothing is registered and no service is enabled: Shaula pre-registers an
# ephemeral runner and starts `forgejo-runner one-job` itself.

RUNNER_VERSION=13.1.0
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) RUNNER_SHA256=29dae21e93f0eab5cdf3564008d44603c74770b41a4f4f1aceed172c774bc376 ;;
  arm64) RUNNER_SHA256=4a18a9a2aad9619e61aca5d81d2c69cc624b26af8605118bfc4729ff994d12d3 ;;
  *) echo "Unsupported runner architecture: $ARCH" >&2; exit 1 ;;
esac
RUNNER_DIR=/opt/forgejo-runner

install -d -m 0755 "$RUNNER_DIR"
curl -fsSL --retry 3 -o /tmp/forgejo-runner \
  "https://code.forgejo.org/forgejo/runner/releases/download/v${RUNNER_VERSION}/forgejo-runner-${RUNNER_VERSION}-linux-${ARCH}"
printf '%s  %s\n' "$RUNNER_SHA256" /tmp/forgejo-runner | sha256sum --check --strict
install -o root -g root -m 0755 /tmp/forgejo-runner "$RUNNER_DIR/forgejo-runner"
rm -f /tmp/forgejo-runner
"$RUNNER_DIR/forgejo-runner" --version
