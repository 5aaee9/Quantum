#!/usr/bin/env bash
set -euo pipefail

test -s "$1"
qemu-img check "$1"
