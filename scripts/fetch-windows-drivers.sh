#!/usr/bin/env bash

# Fetch the Fedora virtio-win ISO and extract the drivers needed by the
# windows-2025-runner packer target into ./drivers (they land on the
# provision ISO via cd_files).
#
# Requires bsdtar (apt: libarchive-tools) or xorriso for extraction.
#
# virtio-win.iso layout quirks (stable-virtio, 0.1.302+):
#   - NetKVM/vioserial live under <dev>/<os>/amd64
#   - vioscsi/viostor 2k25 are hard-links onto a flat amd64/<os>/ tree,
#     so that tree has to be extracted as well
#   - some legacy entries collide (same path twice); extraction of the
#     paths we care about is verified explicitly below
#   - extracted files are read-only

set -euo pipefail

VIRTIO_ISO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
ISO_PATH="drivers/virtio-win.iso"

mkdir -p drivers
if [ ! -f "$ISO_PATH" ]; then
    curl -fSL --retry 3 -o "$ISO_PATH" "$VIRTIO_ISO_URL"
fi

chmod -R u+w drivers 2>/dev/null || true

if command -v bsdtar >/dev/null 2>&1; then
    # NB || true: legacy entries collide on case-duplicate names; the
    #    integrity check below asserts that everything we need made it out.
    (cd drivers && bsdtar -xf virtio-win.iso \
        "amd64/2k25" "amd64/w11" \
        "NetKVM/2k22" \
        "vioscsi/2k25" "vioscsi/w11" \
        "vioserial/2k25" \
        "viostor/2k25" "viostor/w11" \
        "virtio-win-guest-tools.exe" || true)
elif command -v xorriso >/dev/null 2>&1; then
    xorriso -osirrox on -indev "$ISO_PATH" \
        -extract /amd64/2k25 drivers/amd64/2k25 \
        -extract /amd64/w11 drivers/amd64/w11 \
        -extract /NetKVM/2k22 drivers/NetKVM/2k22 \
        -extract /vioscsi/2k25 drivers/vioscsi/2k25 \
        -extract /vioscsi/w11 drivers/vioscsi/w11 \
        -extract /vioserial/2k25 drivers/vioserial/2k25 \
        -extract /viostor/2k25 drivers/viostor/2k25 \
        -extract /viostor/w11 drivers/viostor/w11 \
        -extract /virtio-win-guest-tools.exe drivers/virtio-win-guest-tools.exe
else
    echo "error: need bsdtar (libarchive-tools) or xorriso to extract $ISO_PATH" >&2
    exit 1
fi

chmod -R u+w drivers

# integrity check: every file the packer cd_files globs expect.
missing=0
for f in \
    drivers/vioscsi/2k25/amd64/vioscsi.inf \
    drivers/viostor/2k25/amd64/viostor.inf \
    drivers/NetKVM/2k22/amd64/netkvm.inf \
    drivers/vioserial/2k25/amd64/vioser.inf \
    drivers/virtio-win-guest-tools.exe; do
    if [ ! -f "$f" ]; then
        echo "error: expected $f after extraction" >&2
        missing=1
    fi
done
[ "$missing" = 0 ] || exit 1

# ---------------------------------------------------------------------------
# Provisioner payloads. The Windows guest cannot establish a single TCP
# connection on ANY QEMU NIC/backend we tried (virtio 2k22+2k25, e1000,
# e1000e, rtl8139; slirp AND tap) — ICMP/UDP flow but TCP never emits a
# segment (virtio-win NetKVM datapath bugs on Server 2025 + a deeper
# guest-side TCP failure). So the build runs fully OFFLINE: every payload
# the provisioners need is downloaded HERE on the host (which has normal
# networking) and shipped on the provision ISO; the guest scripts install
# from the CD and never touch the network. communicator="none".
# ---------------------------------------------------------------------------
mkdir -p drivers/payloads

fetch() {  # fetch <output-file> <url> [must-match]
    local out="$1" url="$2"
    if [ ! -s "$out" ]; then
        echo "fetching $out"
        curl -fSL --retry 3 -o "$out" "$url"
    fi
    [ -s "$out" ] || { echo "error: $out empty after fetch" >&2; exit 1; }
}

# latest-release asset URL resolver via the GitHub API.
gh_asset() {  # gh_asset <repo> <asset-glob>
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
        | grep -oE '"browser_download_url": *"[^"]+"' \
        | sed -E 's/.*"(https:[^"]+)".*/\1/' \
        | grep -iE "$2" | head -1
}

fetch drivers/OpenSSH-Win64.zip \
    "https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64.zip"

fetch drivers/payloads/Git-64-bit.exe \
    "$(gh_asset git-for-windows/git 'Git-.*-64-bit\.exe')"

fetch drivers/payloads/PowerShell-win-x64.msi \
    "$(gh_asset PowerShell/PowerShell 'PowerShell-.*-win-x64\.msi')"

fetch drivers/payloads/CloudbaseInitSetup.msi \
    "https://github.com/cloudbase/cloudbase-init/releases/download/1.1.8/CloudbaseInitSetup_1_1_8_x64.msi"

fetch drivers/payloads/EjectVolumeMedia.exe \
    "https://github.com/rgl/EjectVolumeMedia/releases/download/v1.0.0/EjectVolumeMedia.exe"

fetch drivers/payloads/actions-runner-win-x64.zip \
    "$(gh_asset actions/runner 'actions-runner-win-x64-[0-9.]+\.zip')"

echo "virtio drivers + all provisioner payloads ready under drivers/"
