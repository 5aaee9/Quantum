#!/usr/bin/env bash
# Fresh-UEFI/TPM ConfigDrive clone test. Leaves the template disk unchanged.
set -euo pipefail
image=$(realpath "${1:?Usage: $0 image.qcow2}")
for tool in qemu-system-x86_64 swtpm xorriso ssh sshpass node; do command -v "$tool" >/dev/null; done
work=$(mktemp -d)
vm_pid='' tpm_pid=''
cleanup() {
    for pid in "$vm_pid" "$tpm_pid"; do
        if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
    done
    # The ConfigDrive ISO contains an ephemeral password: never retain it.
    rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/seed/openstack/latest" "$work/tpm"
ssh-keygen -q -t ed25519 -N '' -f "$work/key"
password=$(openssl rand -hex 24)
export SMOKE_PASSWORD="${password}aA1!" SMOKE_WORK="$work"
node <<'JS'
const fs=require('fs'),path=process.env.SMOKE_WORK;
fs.writeFileSync(`${path}/seed/openstack/latest/meta_data.json`, JSON.stringify({
  uuid:require('crypto').randomUUID(),hostname:'win11-smoke',admin_pass:process.env.SMOKE_PASSWORD,
  public_keys:{smoke:fs.readFileSync(`${path}/key.pub`,'utf8').trim()}
}));
JS
xorriso -as mkisofs -o "$work/configdrive.iso" -V config-2 -J -r "$work/seed" >/dev/null 2>&1
firmware=/usr/share/OVMF/OVMF_CODE_4M.fd
[[ ! -f /usr/share/OVMF/OVMF_CODE_4M.secboot.fd ]] || firmware=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
cp /usr/share/OVMF/OVMF_VARS_4M.fd "$work/vars.fd"
chmod u+w "$work/vars.fd"
swtpm socket --tpm2 --tpmstate dir="$work/tpm" --ctrl type=unixio,path="$work/tpm.sock" --flags not-need-init,startup-clear &
tpm_pid=$!
for ((i=0; i<50; i++)); do [[ ! -S "$work/tpm.sock" ]] || break; sleep 0.1; done
[[ -S "$work/tpm.sock" ]]
# An occupied forwarding port fails QEMU rather than contacting another guest:
# only the generated key is accepted by the test connection.
port=${WINDOWS_SMOKE_PORT:-12211}
qemu-system-x86_64 -machine q35,accel=kvm -cpu host -m 4096 -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file="$firmware" \
    -drive if=pflash,format=raw,file="$work/vars.fd" \
    -drive if=none,id=os,format=qcow2,snapshot=on,file="$image" \
    -device virtio-scsi-pci,id=scsi0 -device scsi-hd,drive=os \
    -drive media=cdrom,readonly=on,file="$work/configdrive.iso" \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:"$port"-:22 -device virtio-net-pci,netdev=net0 \
    -chardev socket,id=tpm,path="$work/tpm.sock" -tpmdev emulator,id=tpm0,chardev=tpm -device tpm-tis,tpmdev=tpm0 \
    -device virtio-serial-pci \
    -chardev socket,id=qga,path="$work/qga.sock",server=on,wait=off \
    -device virtserialport,chardev=qga,name=org.qemu.guest_agent.0 \
    -display none -serial file:windows-11-smoke-serial.log &
vm_pid=$!
args=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new
      -o UserKnownHostsFile="$work/known_hosts" -i "$work/key" -p "$port" Administrator@127.0.0.1)
ready=false
for ((i=0; i<90; i++)); do
    kill -0 "$vm_pid"
    if ssh "${args[@]}" hostname > "$work/hostname" 2>/dev/null && grep -qi '^win11-smoke' "$work/hostname"; then
        ready=true; break
    fi
    sleep 10
done
"$ready" || { echo 'ConfigDrive hostname/key login did not converge in 15 minutes' >&2; exit 1; }
encoded=$(iconv -f UTF-8 -t UTF-16LE tests/windows-11-guest.ps1 | base64 -w0)
# shellcheck disable=SC2029 # Encoded script is intentionally expanded locally.
ssh "${args[@]}" "powershell -NoProfile -EncodedCommand $encoded"
# Independently check metadata password injection, not only SSH public keys.
SSHPASS="$SMOKE_PASSWORD" sshpass -e ssh -o ConnectTimeout=10 -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no -o UserKnownHostsFile="$work/known_hosts" -p "$port" \
    Administrator@127.0.0.1 hostname | grep -qi '^win11-smoke'
echo 'PASS: ConfigDrive password authentication'
ssh "${args[@]}" 'shutdown /s /t 0' || true
