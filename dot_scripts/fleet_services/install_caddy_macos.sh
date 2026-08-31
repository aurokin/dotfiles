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
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer owns macOS Caddy services only." >&2
  exit 2
fi

brew_caddy="/opt/homebrew/opt/caddy/bin/caddy"
if [[ ! -x "$brew_caddy" ]]; then
  echo "Homebrew Caddy is missing; run brew install caddy." >&2
  exit 1
fi
reported="$($brew_caddy version | awk '{print $1}' | sed 's/^v//')"
if [[ "$reported" != "$CADDY_VERSION" ]]; then
  echo "Homebrew Caddy reported $reported, expected $CADDY_VERSION." >&2
  exit 1
fi

source_config="$script_dir/Caddyfile"
candidate="$(mktemp)"
plist_candidate="$(mktemp)"
cleanup() { rm -f "$candidate" "$plist_candidate"; }
trap cleanup EXIT
cp "$source_config" "$candidate"
$brew_caddy fmt --overwrite "$candidate" >/dev/null
$brew_caddy validate --adapter caddyfile --config "$candidate" >/dev/null

runtime_dir="/usr/local/lib/auro-services/caddy/$CADDY_VERSION"
runtime_bin="$runtime_dir/caddy"
logs_dir="/var/log/auro-caddy"
plist_path="/Library/LaunchDaemons/com.auro.caddy.plist"

cat >"$plist_candidate" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.auro.caddy</string>
  <key>ProgramArguments</key>
  <array>
    <string>$runtime_bin</string>
    <string>run</string>
    <string>--config</string><string>/etc/caddy/Caddyfile</string>
    <string>--adapter</string><string>caddyfile</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$logs_dir/service.log</string>
  <key>StandardErrorPath</key><string>$logs_dir/service.log</string>
</dict>
</plist>
EOF
plutil -lint "$plist_candidate" >/dev/null

echo "Validated macOS Caddy $CADDY_VERSION candidate for port 80 -> 127.0.0.1:1355."
if [[ "$apply" != 1 ]]; then
  exit 0
fi

if ! launchctl print "gui/$(id -u)/com.auro.portless" >/dev/null 2>&1; then
  echo "Auro Portless LaunchAgent is not active; refusing Caddy cutover." >&2
  exit 1
fi
if ! lsof -nP -iTCP:1355 -sTCP:LISTEN | grep -q LISTEN; then
  echo "Portless has no listener on port 1355; refusing Caddy cutover." >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
sudo install -d -o root -g wheel -m 0755 "$runtime_dir" /etc/caddy "$logs_dir"
sudo install -o root -g wheel -m 0755 "$brew_caddy" "$runtime_bin"
sudo "$runtime_bin" version >/dev/null
if sudo test -f /etc/caddy/Caddyfile; then
  sudo cp -p /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.pre-auro-$stamp"
fi
if sudo test -f "$plist_path"; then
  sudo cp -p "$plist_path" "$plist_path.pre-auro-$stamp"
fi
sudo install -o root -g wheel -m 0644 "$candidate" /etc/caddy/Caddyfile
sudo install -o root -g wheel -m 0644 "$plist_candidate" "$plist_path"
sudo "$runtime_bin" validate --adapter caddyfile --config /etc/caddy/Caddyfile >/dev/null
sudo launchctl bootout system/com.auro.caddy >/dev/null 2>&1 || true
sudo launchctl bootstrap system "$plist_path"
sudo launchctl kickstart -k system/com.auro.caddy
sudo launchctl print system/com.auro.caddy >/dev/null

echo "Caddy LaunchDaemon is active with the fleet development ingress config."
