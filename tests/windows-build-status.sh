#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
log=$(mktemp)
trap 'rm -f "$log"' EXIT
reject() {
    if bash scripts/check-windows-build.sh "$log"; then
        echo 'FAIL: invalid build was accepted' >&2
        exit 1
    fi
}
reject
printf 'PROV: 12:34:56 watchdog armed\r\n' > "$log"
reject
printf 'PROV: 12:34:56 BUILD_FAILED: installer failed\r\n' > "$log"
reject
printf 'PROV: 12:34:56 BUILD_SUCCESS\r\n' > "$log"
bash scripts/check-windows-build.sh "$log"
printf 'PROV: 12:35:00 BUILD_FAILED: second invocation\r\n' >> "$log"
reject
echo 'PASS: success gate rejects missing, failed and contradictory completion records.'
