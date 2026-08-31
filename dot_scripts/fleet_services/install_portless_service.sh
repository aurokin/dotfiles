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

os="$(uname -s)"
case "$os" in
  Darwin)
    node_root="/opt/homebrew/opt/node@24"
    ;;
  Linux)
    node_root="/home/linuxbrew/.linuxbrew/opt/node@24"
    ;;
  *)
    echo "Unsupported OS: $os" >&2
    exit 2
    ;;
esac

node_bin="$node_root/bin/node"
npm_bin="$node_root/bin/npm"
if [[ ! -x "$node_bin" || ! -x "$npm_bin" ]]; then
  echo "Stable service Node is missing under $node_root; run brew install node@24." >&2
  exit 1
fi

node_major="$($node_bin -p 'process.versions.node.split(".")[0]')"
if [[ "$node_major" != "24" ]]; then
  echo "Expected service Node 24, found $($node_bin --version)." >&2
  exit 1
fi

service_root="$HOME/.local/share/auro-services/portless"
versions_root="$service_root/versions"
version_root="$versions_root/$PORTLESS_VERSION"
current_link="$service_root/current"
entry_rel="node_modules/portless/dist/cli.js"
entry_path="$version_root/$entry_rel"
mkdir -p "$versions_root"

if [[ ! -f "$entry_path" ]]; then
  staging="$(mktemp -d "$service_root/.staging-$PORTLESS_VERSION.XXXXXX")"
  cleanup_staging() { rm -rf "$staging"; }
  trap cleanup_staging EXIT
  "$npm_bin" install \
    --prefix "$staging" \
    --omit=dev \
    --no-audit \
    --no-fund \
    --ignore-scripts=false \
    "portless@$PORTLESS_VERSION"
  staged_entry="$staging/$entry_rel"
  if [[ ! -f "$staged_entry" ]]; then
    echo "Portless entrypoint missing after install: $staged_entry" >&2
    exit 1
  fi
  reported="$($node_bin "$staged_entry" --version)"
  if [[ "$reported" != "$PORTLESS_VERSION" ]]; then
    echo "Portless candidate reported $reported, expected $PORTLESS_VERSION." >&2
    exit 1
  fi
  mv "$staging" "$version_root"
  trap - EXIT
fi

reported="$($node_bin "$entry_path" --version)"
if [[ "$reported" != "$PORTLESS_VERSION" ]]; then
  echo "Installed Portless reported $reported, expected $PORTLESS_VERSION." >&2
  exit 1
fi

link_tmp="$service_root/.current.$$"
rm -f "$link_tmp"
ln -s "versions/$PORTLESS_VERSION" "$link_tmp"
python3 - "$link_tmp" "$current_link" <<'PY'
import os
import sys
os.replace(sys.argv[1], sys.argv[2])
PY

short_host="$(hostname -s 2>/dev/null || hostname)"
short_host="${short_host%%.*}"
short_host="$(printf '%s' "$short_host" | tr '[:upper:]' '[:lower:]')"
case "$short_host" in
  ''|*[!a-z0-9-]*)
    echo "Unsafe short hostname for Portless TLD: $short_host" >&2
    exit 1
    ;;
esac

logs_dir="$HOME/.local/state/auro-services/portless"
mkdir -p "$logs_dir" "$HOME/.portless"
service_entry="$current_link/$entry_rel"

render_linux_unit() {
  cat <<EOF
[Unit]
Description=Auro Portless development router
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h
Environment=HOME=$HOME
Environment=PORTLESS_STATE_DIR=$HOME/.portless
Environment=PORTLESS_PORT=1355
Environment=PORTLESS_HTTPS=0
Environment=PORTLESS_LAN=0
Environment=PORTLESS_SYNC_HOSTS=0
Environment=PORTLESS_TLD=$short_host.home.arpa,localhost
ExecStart=$node_bin $service_entry proxy start --foreground --port 1355 --no-tls --tld $short_host.home.arpa --tld localhost
Restart=on-failure
RestartSec=3
KillSignal=SIGTERM
TimeoutStopSec=10
StandardOutput=append:$logs_dir/service.log
StandardError=append:$logs_dir/service.log

[Install]
WantedBy=default.target
EOF
}

render_macos_plist() {
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.auro.portless</string>
  <key>ProgramArguments</key>
  <array>
    <string>$node_bin</string>
    <string>$service_entry</string>
    <string>proxy</string><string>start</string>
    <string>--foreground</string>
    <string>--port</string><string>1355</string>
    <string>--no-tls</string>
    <string>--tld</string><string>$short_host.home.arpa</string>
    <string>--tld</string><string>localhost</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$HOME</string>
    <key>PORTLESS_STATE_DIR</key><string>$HOME/.portless</string>
    <key>PORTLESS_PORT</key><string>1355</string>
    <key>PORTLESS_HTTPS</key><string>0</string>
    <key>PORTLESS_LAN</key><string>0</string>
    <key>PORTLESS_SYNC_HOSTS</key><string>0</string>
    <key>PORTLESS_TLD</key><string>$short_host.home.arpa,localhost</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$logs_dir/service.log</string>
  <key>StandardErrorPath</key><string>$logs_dir/service.log</string>
</dict>
</plist>
EOF
}

if [[ "$os" == "Linux" ]]; then
  if systemctl is-active --quiet portless.service 2>/dev/null; then
    echo "A legacy system Portless service is active; refusing parallel ownership." >&2
    exit 3
  fi
  unit_dir="$HOME/.config/systemd/user"
  unit_path="$unit_dir/auro-portless.service"
  mkdir -p "$unit_dir"
  tmp="$(mktemp "$unit_dir/.auro-portless.XXXXXX")"
  render_linux_unit >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$unit_path"
  echo "Prepared $unit_path with Portless $PORTLESS_VERSION and $($node_bin --version)."
  if [[ "$apply" == 1 ]]; then
    systemctl --user daemon-reload
    systemctl --user enable --now auro-portless.service
    loginctl enable-linger
    systemctl --user is-active --quiet auro-portless.service
    echo "Auro Portless user service is active."
  fi
else
  if launchctl print system/sh.portless.proxy >/dev/null 2>&1; then
    echo "A legacy system Portless LaunchDaemon is active; refusing parallel ownership." >&2
    exit 3
  fi
  plist_dir="$HOME/Library/LaunchAgents"
  plist_path="$plist_dir/com.auro.portless.plist"
  mkdir -p "$plist_dir"
  tmp="$(mktemp "$plist_dir/.com.auro.portless.XXXXXX")"
  render_macos_plist >"$tmp"
  plutil -lint "$tmp" >/dev/null
  chmod 600 "$tmp"
  mv "$tmp" "$plist_path"
  echo "Prepared $plist_path with Portless $PORTLESS_VERSION and $($node_bin --version)."
  if [[ "$apply" == 1 ]]; then
    domain="gui/$(id -u)"
    launchctl bootout "$domain/com.auro.portless" >/dev/null 2>&1 || true
    launchctl bootstrap "$domain" "$plist_path"
    launchctl kickstart -k "$domain/com.auro.portless"
    launchctl print "$domain/com.auro.portless" >/dev/null
    echo "Auro Portless LaunchAgent is active."
  fi
fi
