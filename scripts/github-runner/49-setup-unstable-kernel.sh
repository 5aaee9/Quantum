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

runtime_packages=()
for package in "${kernel_packages[@]}"; do
  curl --fail --location --silent --show-error \
    --output "$tmp_dir/$(basename "$package")" \
    "$mainline_url$package"
  case "$package" in
    linux-image-unsigned-*|linux-modules-*) runtime_packages+=("./$package") ;;
  esac
done

if ((${#runtime_packages[@]} != 2)); then
  echo "Expected a kernel image and modules at $mainline_url" >&2
  exit 1
fi

# Daily headers can require libraries from a newer Ubuntu release. The
# matching image and modules are sufficient to boot the daily kernel.
pushd "$tmp_dir" >/dev/null
if apt-get --simulate install ./*.deb; then
  apt-get install --yes ./*.deb
else
  echo 'Daily kernel headers are unavailable for this Ubuntu release. Installing the image and modules only.' >&2
  apt-get install --yes "${runtime_packages[@]}"
fi
popd >/dev/null

if grep -qE '^GRUB_DEFAULT=' /etc/default/grub; then
  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
else
  printf '\nGRUB_DEFAULT=0\n' >> /etc/default/grub
fi
update-grub

installed_kernel=$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -n1)
echo "Installed unstable kernel: $installed_kernel"
