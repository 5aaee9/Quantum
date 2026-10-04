#!/usr/bin/env bash
# Verify a read-only mounted Windows partition after a local image build.
set -euo pipefail
root="${1:?usage: check-windows-image.sh MOUNTPOINT}"
failed=0
for path in \
    'Program Files/Git/bin/git.exe' \
    'Program Files/PowerShell/7/pwsh.exe' \
    'Program Files/OpenSSH/sshd.exe' \
    'Program Files/Cloudbase Solutions/Cloudbase-Init/conf/cloudbase-init.conf' \
    'actions-runner/bin/Runner.Listener.exe' \
    'Windows/System32/Sysprep/Sysprep_succeeded.tag'; do
    if [ ! -f "$root/$path" ]; then
        echo "FAIL: missing $path" >&2
        failed=1
    fi
done
[ "$failed" = 0 ] || exit 1
echo 'PASS: installed payloads and Sysprep success tag are present.'
