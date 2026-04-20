#!/usr/bin/env bash

set -ex


# Add `sync` so Packer doesn't quit too early, before the large file is deleted.
sync

fstrim --all --verbose
