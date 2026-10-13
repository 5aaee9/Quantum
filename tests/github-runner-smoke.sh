#!/usr/bin/env bash
set -euxo pipefail

test "$(dpkg --print-architecture)" = arm64
test "$(uname -m)" = aarch64
. /etc/os-release
test "$VERSION_ID" = 24.04

# Each command must execute successfully, catching wrong-architecture downloads.
/opt/actions-runner/bin/Runner.Listener --version
/opt/forgejo-runner/forgejo-runner --version
/opt/gitlab-runner/gitlab-runner --version
docker --version
docker buildx version
docker compose version
node --version
npm --version
yarn --version
python3 --version
python3 -m pip --version
python3 -m venv /tmp/runner-smoke-venv
rm -rf /tmp/runner-smoke-venv
gh --version
kubectl version --client
helm version --short
terraform version
git lfs version
psql --version
mysql --version

id runner
id -nG runner | grep -w docker
visudo -cf /etc/sudoers.d/runner
systemctl is-enabled docker.service containerd.service
systemctl is-active docker.service
test "$(systemctl is-enabled apt-daily.timer)" = masked
test "$(systemctl is-enabled apt-daily-upgrade.timer)" = masked
# No deployment tokens or registration state may leak into the template.
test ! -e /opt/actions-runner/.runner
test ! -e /opt/actions-runner/.credentials
test ! -e /etc/gitlab-runner/config.toml
