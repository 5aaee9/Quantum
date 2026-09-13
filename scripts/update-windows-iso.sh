#!/usr/bin/env bash

# Update the Windows Server eval ISO url/checksum in
# targets/windows-2025-runner/basic.pkr.hcl from
# https://github.com/rgl/windows-evaluation-isos-scraper (which scrapes the
# Microsoft Evaluation Center when links rotate).
#
# If you mirrored the ISO to alist, set WINDOWS_2025_ISO_URL instead and
# this script is not needed.

set -euo pipefail

VAR_FILE=targets/windows-2025-runner/basic.pkr.hcl

json=$(curl -fsSL \
    https://raw.githubusercontent.com/rgl/windows-evaluation-isos-scraper/main/data/windows-2025.json)

url=$(jq -r .url <<<"$json")
sha=$(jq -r .checksum <<<"$json")
created=$(jq -r .createdAt <<<"$json")
size=$(jq -r .size <<<"$json")

echo "latest eval ISO: $created ($(numfmt --to=iec "$size"))"
echo "  url:      $url"
echo "  sha256:   $sha"

sed -i -E \
    "s|(default = env\\(\"WINDOWS_2025_ISO_URL\"\\) != \"\" \\? env\\(\"WINDOWS_2025_ISO_URL\"\\) : \")[^\"]+(\")|\\1${url}\\2|" \
    "$VAR_FILE"
sed -i -E \
    "s|(default = env\\(\"WINDOWS_2025_ISO_CHECKSUM\"\\) != \"\" \\? env\\(\"WINDOWS_2025_ISO_CHECKSUM\"\\) : \"sha256:)[0-9a-f]+(\")|\\1${sha}\\2|" \
    "$VAR_FILE"

echo "updated $VAR_FILE"
