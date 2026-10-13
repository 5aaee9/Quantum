#!/usr/bin/env bash

set -ex

# Pre-install the official gitlab-runner binary for Shaula's GitLab VM
# bootstrap (`gitlab-runner run-single --max-builds 1`). Pinned version +
# SHA-256 from https://gitlab-runner-downloads.s3.amazonaws.com/v<ver>/release.sha256.
#
# Deliberately the bare binary, not the gitlab-runner .deb: the package
# creates a `gitlab-runner` user and enables a persistent `gitlab-runner run`
# service, which would poll GitLab with any token it finds. Shaula starts a
# single run-single process per VM and must remain the only runner.

RUNNER_VERSION=19.4.1
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) RUNNER_SHA256=5a159b36c5ff54fda9248e00bb0cdfb62c1112ab3741f5282c04a41e94da1306 ;;
  arm64) RUNNER_SHA256=9763a63f7bc2319119f80de41d1d414465b5268d072bcd55266020b989e93ee9 ;;
  *) echo "Unsupported runner architecture: $ARCH" >&2; exit 1 ;;
esac
RUNNER_DIR=/opt/gitlab-runner

install -d -m 0755 "$RUNNER_DIR"
curl -fsSL --retry 3 -o /tmp/gitlab-runner \
  "https://gitlab-runner-downloads.s3.amazonaws.com/v${RUNNER_VERSION}/binaries/gitlab-runner-linux-${ARCH}"
printf '%s  %s\n' "$RUNNER_SHA256" /tmp/gitlab-runner | sha256sum --check --strict
install -o root -g root -m 0755 /tmp/gitlab-runner "$RUNNER_DIR/gitlab-runner"
rm -f /tmp/gitlab-runner
"$RUNNER_DIR/gitlab-runner" --version
