#!/usr/bin/env bash

set -euo pipefail

# The hardened installer requires explicit idle/restart authorization.
# Refuse BEFORE package installs, legacy shutdown, or configuration changes.
echo "Legacy migration paused: a separately reviewed idle/ownership cutover is required; no changes made." >&2
exit 3

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ "${1:-}" != "--apply" || -n "${2:-}" ]]; then
  echo "Usage: $0 --apply" >&2
  exit 2
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This migration owns macOS legacy services only." >&2
  exit 2
fi
if ! launchctl print system/sh.portless.proxy >/dev/null 2>&1; then
  echo "Legacy system Portless LaunchDaemon is not loaded; use the normal installers." >&2
  exit 2
fi

routes_file="$HOME/.portless/routes.json"
route_count="$(python3 - "$routes_file" <<'PY'
import json
import sys
try:
    data=json.load(open(sys.argv[1]))
except FileNotFoundError:
    data=[]
print(len(data))
PY
)"
if [[ "$route_count" != 0 ]]; then
  echo "Legacy Portless has $route_count active routes; refusing migration." >&2
  exit 3
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
legacy_plist="/Library/LaunchDaemons/sh.portless.proxy.plist"
retired_plist="$legacy_plist.retired-$stamp"
legacy_stopped=0
success=0
rollback() {
  if [[ "$success" != 1 && "$legacy_stopped" == 1 ]]; then
    echo "Migration failed; restoring legacy Portless LaunchDaemon." >&2
    launchctl bootout "gui/$(id -u)/com.auro.portless" >/dev/null 2>&1 || true
    sudo launchctl bootout system/com.auro.caddy >/dev/null 2>&1 || true
    if sudo test -f "$retired_plist"; then
      sudo mv "$retired_plist" "$legacy_plist"
      sudo launchctl bootstrap system "$legacy_plist" >/dev/null 2>&1 || true
    fi
  fi
}
trap rollback EXIT

sudo launchctl bootout system/sh.portless.proxy >/dev/null 2>&1 || true
sudo mv "$legacy_plist" "$retired_plist"
legacy_stopped=1
"$script_dir/install_portless_service.sh" --apply
"$script_dir/install_caddy_macos.sh" --apply

launchctl print "gui/$(id -u)/com.auro.portless" >/dev/null
launchctl print system/com.auro.caddy >/dev/null
if launchctl print system/sh.portless.proxy >/dev/null 2>&1; then
  echo "Legacy Portless LaunchDaemon is still loaded after migration." >&2
  exit 1
fi
success=1
trap - EXIT

echo "Migrated legacy macOS Portless LaunchDaemon to dotfiles-owned Portless plus Caddy."
