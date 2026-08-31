#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$script_dir/versions.env"

apply=0
if [[ "${1:-}" == "--apply" ]]; then
  apply=1
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--apply]" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This installer owns Linux Caddy services only." >&2
  exit 2
fi

caddy_bin="/usr/bin/caddy"
if [[ ! -x "$caddy_bin" ]]; then
  echo "Native Caddy is missing at $caddy_bin; install the reviewed distro package first." >&2
  exit 1
fi

reported="$($caddy_bin version | awk '{print $1}' | sed 's/^v//')"
if [[ "$reported" != "$CADDY_VERSION" ]]; then
  echo "Caddy reported $reported, expected $CADDY_VERSION." >&2
  exit 1
fi

source_config="$script_dir/Caddyfile"
if [[ ! -f "$source_config" ]]; then
  echo "Missing Caddyfile: $source_config" >&2
  exit 1
fi

candidate="$(mktemp)"
cleanup() { rm -f "$candidate"; }
trap cleanup EXIT
cp "$source_config" "$candidate"
$caddy_bin fmt --overwrite "$candidate" >/dev/null
$caddy_bin validate --adapter caddyfile --config "$candidate" >/dev/null

echo "Validated Caddy $CADDY_VERSION candidate for port 80 -> 127.0.0.1:1355."
if [[ "$apply" != 1 ]]; then
  exit 0
fi

if ! systemctl --user is-active --quiet auro-portless.service; then
  echo "Auro Portless user service is not active; refusing Caddy cutover." >&2
  exit 1
fi
if ! ss -lntp | grep -q ':1355 '; then
  echo "Portless has no loopback listener on port 1355; refusing Caddy cutover." >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
if sudo test -f /etc/caddy/Caddyfile; then
  sudo cp -p /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.pre-auro-$stamp"
fi
sudo install -d -m 0755 /etc/caddy
sudo install -o root -g root -m 0644 "$candidate" /etc/caddy/Caddyfile
sudo "$caddy_bin" validate --adapter caddyfile --config /etc/caddy/Caddyfile >/dev/null
sudo systemctl enable caddy.service >/dev/null
if systemctl is-active --quiet caddy.service; then
  sudo systemctl reload caddy.service
else
  sudo systemctl start caddy.service
fi
systemctl is-active --quiet caddy.service

echo "Caddy service is active with the fleet development ingress config."
