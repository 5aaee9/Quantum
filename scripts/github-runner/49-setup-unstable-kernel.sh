#!/usr/bin/env bash

set -euxo pipefail

# Install the newest successful Ubuntu mainline daily kernel. Mainline builds
# are deliberately unsupported and do not receive security updates; this is
# intended for kernel testing on the GitHub Runner image.
export DEBIAN_FRONTEND=noninteractive

mainline_url="https://kernel.ubuntu.com/mainline/daily/current/amd64/"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

index=$(curl --fail --location --silent --show-error "$mainline_url")
mapfile -t kernel_packages < <(
  printf '%s\n' "$index" \
    | grep -oE 'href="[^"]+\.deb"' \
    | cut -d'"' -f2 \
    | grep -E '^linux-(headers|image-unsigned|modules)-.*_(amd64|all)\.deb$' \
    | sort -u
)

if ((${#kernel_packages[@]} != 4)); then
  echo "Expected four amd64 kernel packages at $mainline_url, found ${#kernel_packages[@]}" >&2
  printf '%s\n' "${kernel_packages[@]}" >&2
  exit 1
fi

for package in "${kernel_packages[@]}"; do
  curl --fail --location --silent --show-error \
    --output "$tmp_dir/$(basename "$package")" \
    "$mainline_url$package"
done

# Install the package set as one transaction so APT can resolve dependencies
# while keeping the matching image, modules, and headers together. The
# mainline image is unsigned by design.
apt-get install --yes "$tmp_dir"/*.deb

if grep -qE '^GRUB_DEFAULT=' /etc/default/grub; then
  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
else
  printf '\nGRUB_DEFAULT=0\n' >> /etc/default/grub
fi
update-grub

installed_kernel=$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -n1)
echo "Installed unstable kernel: $installed_kernel"
