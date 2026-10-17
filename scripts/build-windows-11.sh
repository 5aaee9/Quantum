#!/usr/bin/env bash
# Run from the repository root. Supply the validated UUP output and sidecar.
set -euo pipefail
iso=$(realpath "${1:?Usage: $0 /path/to/windows-11.iso}")
checksum_file="${iso}.sha256"
[[ -s "$checksum_file" ]] || { echo "Missing $checksum_file" >&2; exit 1; }
expected=$(awk 'NR == 1 {print $1}' "$checksum_file")
[[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || { echo 'Invalid SHA256 sidecar' >&2; exit 1; }
actual=$(sha256sum "$iso" | cut -d ' ' -f1)
[[ "$actual" == "$expected" ]] || { echo 'ISO checksum mismatch' >&2; exit 1; }
for tool in packer qemu-img swtpm flock; do command -v "$tool" >/dev/null; done
[[ -r /dev/kvm && -w /dev/kvm ]] || { echo 'Run with access to /dev/kvm' >&2; exit 1; }
# This target has fixed output/socket names; disallow concurrent invocations.
mkdir -p outputs
exec 9>outputs/windows-11.lock
flock -n 9 || { echo 'Another Windows 11 build is running' >&2; exit 1; }
[[ ! -e outputs/windows-11 ]] || { echo 'Move existing outputs/windows-11 aside before rebuilding' >&2; exit 1; }
[[ ! -e windows-11.qcow2 ]] || { echo 'Move existing windows-11.qcow2 aside before rebuilding' >&2; exit 1; }
bash scripts/fetch-windows-drivers.sh windows-11
packer init targets/windows-11
state=$(mktemp -d)
tpm_pid=''
cleanup() {
    if [[ -n "$tpm_pid" ]]; then kill "$tpm_pid" 2>/dev/null || true; wait "$tpm_pid" 2>/dev/null || true; fi
    rm -rf "$state"
    rm -f windows-11-tpm.sock
}
trap cleanup EXIT
rm -f windows-11-tpm.sock windows-11-serial.log windows-11-monitor.sock windows-11-qga.sock
swtpm socket --tpm2 --tpmstate dir="$state" \
    --ctrl type=unixio,path="$PWD/windows-11-tpm.sock" \
    --flags not-need-init,startup-clear &
tpm_pid=$!
for ((i=0; i<50; i++)); do
    [[ -S windows-11-tpm.sock ]] && break
    kill -0 "$tpm_pid"
    sleep 0.1
done
[[ -S windows-11-tpm.sock ]]
PACKER_LOG=1 PACKER_LOG_PATH="$PWD/packer-windows-11.log" packer build \
    -var 'headless=true' -var "iso_url=$iso" -var "iso_checksum=sha256:$expected" \
    targets/windows-11
bash scripts/check-windows-build.sh windows-11-serial.log
qemu-img check outputs/windows-11/packer-windows-11
qemu-img convert -O qcow2 -c outputs/windows-11/packer-windows-11 windows-11.qcow2
qemu-img check windows-11.qcow2
