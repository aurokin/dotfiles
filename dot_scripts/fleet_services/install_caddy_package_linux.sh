#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$script_dir/versions.env"

if [[ "${1:-}" != "--apply" || -n "${2:-}" ]]; then
  echo "Usage: $0 --apply" >&2
  exit 2
fi
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This installer owns Linux packages only." >&2
  exit 2
fi

if [[ -f /etc/debian_version ]]; then
  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64) asset="caddy_${CADDY_VERSION}_linux_amd64.deb" ;;
    arm64) asset="caddy_${CADDY_VERSION}_linux_arm64.deb" ;;
    *) echo "Unsupported Debian architecture: $arch" >&2; exit 2 ;;
  esac
  base="https://github.com/caddyserver/caddy/releases/download/v$CADDY_VERSION"
  tmp="$(mktemp -d)"
  cleanup() { rm -rf "$tmp"; }
  trap cleanup EXIT
  curl -fsSL "$base/caddy_${CADDY_VERSION}_checksums.txt" -o "$tmp/checksums.txt"
  curl -fL "$base/$asset" -o "$tmp/$asset"
  grep -E "[[:space:]]$asset$" "$tmp/checksums.txt" >"$tmp/expected.txt"
  if [[ ! -s "$tmp/expected.txt" ]]; then
    echo "Official checksum entry missing for $asset." >&2
    exit 1
  fi
  (cd "$tmp" && sha512sum --check expected.txt)
  sudo apt-get install -y "$tmp/$asset"
elif [[ -f /etc/arch-release ]]; then
  sudo pacman -S --needed --noconfirm caddy
else
  echo "Unsupported Linux distribution for Caddy package ownership." >&2
  exit 2
fi

reported="$(/usr/bin/caddy version | awk '{print $1}' | sed 's/^v//')"
if [[ "$reported" != "$CADDY_VERSION" ]]; then
  echo "Installed Caddy reported $reported, expected $CADDY_VERSION." >&2
  exit 1
fi

echo "Installed native Caddy $reported."
