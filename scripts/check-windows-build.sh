#!/usr/bin/env bash
# communicator=none only observes power-off. Require the provisioner's
# post-validation, post-Sysprep success record before accepting the image.
set -euo pipefail
log="${1:-windows-2025-runner-serial.log}"
if ! grep -aEq '^PROV: [0-9:]+ BUILD_SUCCESS[[:space:]]*$' "$log" ||
    grep -aq 'BUILD_FAILED:' "$log"; then
    echo "Windows provisioning did not complete successfully; inspect $log" >&2
    exit 1
fi
echo 'Windows provisioning and Sysprep completed successfully.'
