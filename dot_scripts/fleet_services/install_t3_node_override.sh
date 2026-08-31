#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" != "--apply" || -n "${2:-}" ]]; then
  echo "Usage: $0 --apply" >&2
  exit 2
fi
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "T3 stable-Node override is Linux-only." >&2
  exit 2
fi

node_bin="/home/linuxbrew/.linuxbrew/opt/node@24/bin/node"
launcher="$HOME/.t3/runtime/service-launcher.mjs"
unit="$HOME/.config/systemd/user/t3code.service"
dropin_dir="$HOME/.config/systemd/user/t3code.service.d"
dropin="$dropin_dir/service-node.conf"

for p in "$node_bin" "$launcher" "$unit"; do
  if [[ ! -e "$p" ]]; then
    echo "Required T3 service artifact missing: $p" >&2
    exit 1
  fi
done
if [[ "$($node_bin -p 'process.versions.node.split(".")[0]')" != 24 ]]; then
  echo "Stable service Node is not major 24." >&2
  exit 1
fi

mkdir -p "$dropin_dir"
tmp="$(mktemp "$dropin_dir/.service-node.XXXXXX")"
cat >"$tmp" <<EOF
[Service]
ExecStart=
ExecStart=$node_bin $launcher
EOF
chmod 600 "$tmp"
mv "$tmp" "$dropin"
systemd-analyze --user verify "$unit"
systemctl --user daemon-reload
systemctl --user restart t3code.service
systemctl --user is-active --quiet t3code.service

actual="$(systemctl --user show t3code.service -p ExecStart --value)"
if [[ "$actual" != *"$node_bin"* ]]; then
  echo "Effective T3 ExecStart does not use stable service Node: $actual" >&2
  exit 1
fi

echo "T3 service now uses stable Node: $($node_bin --version)"
