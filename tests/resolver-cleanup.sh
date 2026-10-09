#!/usr/bin/env bash
# Execute real image cleanup in an isolated filesystem, never the host's /etc.
# Requires bubblewrap, bash, coreutils and findutils.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
bash_bin=$(readlink -f "$(command -v bash)")
core_bin=$(dirname "$(readlink -f "$(command -v rm)")")
find_bin=$(dirname "$(readlink -f "$(command -v find)")")
for mode in stub uplink dangling regular missing; do
  bwrap --unshare-all --die-with-parent \
    --ro-bind / / \
    --proc /proc --dev /dev --tmpfs /tmp \
    --tmpfs /etc --tmpfs /var --tmpfs /root --tmpfs /run \
    --dir /run/systemd/resolve \
    --ro-bind "$root/scripts/generic/98-clear-files.sh" /tmp/cleanup.sh \
    --setenv PATH "$(dirname "$bash_bin"):$core_bin:$find_bin" \
    --setenv HOME /root \
    "$bash_bin" -c '
      set -euo pipefail
      case "$1" in
        stub) target=/run/systemd/resolve/stub-resolv.conf ;;
        uplink) target=/run/systemd/resolve/resolv.conf ;;
        dangling) target=/run/systemd/resolve/stub-resolv.conf ;;
        regular) printf "nameserver 10.0.2.3\n" > /etc/resolv.conf ;;
      esac
      if [[ -n "${target:-}" ]]; then
        [[ "$1" == dangling ]] || printf "nameserver 127.0.0.53\n" > "$target"
        ln -s "$target" /etc/resolv.conf
      fi
      bash /tmp/cleanup.sh >/tmp/cleanup.log 2>&1
      case "$1" in
        stub|uplink|dangling)
          [[ -L /etc/resolv.conf ]] && [[ $(readlink /etc/resolv.conf) == "$target" ]] || {
            echo "FAIL: cleanup removed the $1 resolver symlink" >&2; exit 1;
          } ;;
        regular|missing)
          [[ ! -e /etc/resolv.conf ]] || {
            echo "FAIL: cleanup retained builder DNS" >&2; exit 1;
          } ;;
      esac
      echo "PASS: resolver cleanup ($1)"
    ' bash "$mode"
done
