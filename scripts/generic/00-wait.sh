#!/usr/bin/env bash

set -ex

while true; do
  if [ -f /continue ]; then
    break
  fi

  sleep 1
done
