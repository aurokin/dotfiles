#!/bin/bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Portless service install is macOS-only in these dotfiles; skipping."
  exit 0
fi

if ! command -v portless >/dev/null 2>&1; then
  echo "portless not found; skipping service install."
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node not found; skipping portless service install."
  exit 0
fi

plist="/Library/LaunchDaemons/sh.portless.proxy.plist"
label="sh.portless.proxy"

resolve_path() {
  local path="$1"
  if [[ -z "$path" ]]; then
    return 0
  fi

  perl -MCwd=realpath -e '$p = realpath($ARGV[0]); print defined($p) ? $p : $ARGV[0]; print "\n"' "$path"
}

portless_executable() {
  mise which portless 2>/dev/null || command -v portless
}

current_node="$(resolve_path "$(node -p 'process.execPath')")"
current_portless="$(resolve_path "$(portless_executable)")"

plist_read() {
  /usr/libexec/PlistBuddy -c "Print $1" "$plist" 2>/dev/null || true
}

declare -a reasons=()

if [[ ! -f "$plist" ]]; then
  reasons+=("service plist is missing")
else
  plist_node="$(resolve_path "$(plist_read ':ProgramArguments:0')")"
  plist_portless="$(resolve_path "$(plist_read ':ProgramArguments:1')")"
  plist_command="$(plist_read ':ProgramArguments:2')"
  plist_subcommand="$(plist_read ':ProgramArguments:3')"
  plist_foreground="$(plist_read ':ProgramArguments:4')"
  plist_port_flag="$(plist_read ':ProgramArguments:5')"
  plist_port="$(plist_read ':ProgramArguments:6')"
  plist_https="$(plist_read ':ProgramArguments:7')"
  plist_lan_arg="$(plist_read ':ProgramArguments:8')"
  plist_skip_trust="$(plist_read ':ProgramArguments:9')"
  plist_lan="$(plist_read ':EnvironmentVariables:PORTLESS_LAN')"
  plist_tld="$(plist_read ':EnvironmentVariables:PORTLESS_TLD')"

  if [[ "$plist_node" != "$current_node" ]]; then
    reasons+=("node path changed")
  fi

  if [[ "$plist_portless" != "$current_portless" ]]; then
    reasons+=("portless path changed")
  fi

  if [[ "$plist_command" != "proxy" || "$plist_subcommand" != "start" ]]; then
    reasons+=("service command is not portless proxy start")
  fi

  if [[ "$plist_foreground" != "--foreground" ||
    "$plist_port_flag" != "--port" ||
    "$plist_port" != "443" ||
    "$plist_https" != "--https" ||
    "$plist_lan_arg" != "--lan" ||
    "$plist_skip_trust" != "--skip-trust" ]]; then
    reasons+=("service arguments are not LAN HTTPS on 443")
  fi

  if [[ "$plist_lan" != "1" || "$plist_tld" != "local" ]]; then
    reasons+=("service is not configured for LAN mode")
  fi

  if ! launchctl print "system/$label" >/dev/null 2>&1; then
    reasons+=("launchd service is not loaded")
  fi
fi

if [[ "${#reasons[@]}" -eq 0 ]]; then
  status="$(portless service status 2>/dev/null || true)"
  echo "Portless launchd service is current."
  if grep -q "Proxy on 443: not responding" <<<"$status"; then
    echo "Warning: portless service is installed but the proxy is not responding on 443."
    echo "Current listener on 443:"
    lsof -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null || true
  fi
  exit 0
fi

echo "Portless launchd service needs refresh:"
for reason in "${reasons[@]}"; do
  echo "  - $reason"
done

if [[ ! -t 0 ]]; then
  echo "No interactive terminal is available for sudo; run manually:"
  echo "  portless service install --lan"
  exit 0
fi

sudo -v
PORTLESS_LAN=1 portless service install --lan
portless service status
