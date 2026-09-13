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
        "NetKVM/2k25" \
        "vioscsi/2k25" "vioscsi/w11" \
        "vioserial/2k25" \
        "viostor/2k25" "viostor/w11" \
        "virtio-win-guest-tools.exe" || true)
elif command -v xorriso >/dev/null 2>&1; then
    xorriso -osirrox on -indev "$ISO_PATH" \
        -extract /amd64/2k25 drivers/amd64/2k25 \
        -extract /amd64/w11 drivers/amd64/w11 \
        -extract /NetKVM/2k25 drivers/NetKVM/2k25 \
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
    drivers/NetKVM/2k25/amd64/netkvm.inf \
    drivers/vioserial/2k25/amd64/vioser.inf \
    drivers/virtio-win-guest-tools.exe; do
    if [ ! -f "$f" ]; then
        echo "error: expected $f after extraction" >&2
        missing=1
    fi
done
[ "$missing" = 0 ] || exit 1

echo "virtio drivers ready under drivers/"
