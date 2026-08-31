#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ "${1:-}" != "--apply" || -n "${2:-}" ]]; then
  echo "Usage: $0 --apply" >&2
  exit 2
fi
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This migration owns Linux legacy services only." >&2
  exit 2
fi
if ! systemctl is-active --quiet portless.service; then
  echo "Legacy system Portless service is not active; use the normal installers." >&2
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

"$script_dir/install_caddy_package_linux.sh" --apply
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
sudo cp -p /etc/systemd/system/portless.service "/etc/systemd/system/portless.service.pre-auro-$stamp"

legacy_stopped=0
success=0
rollback() {
  if [[ "$success" != 1 && "$legacy_stopped" == 1 ]]; then
    echo "Migration failed; restoring legacy Portless service." >&2
    systemctl --user disable --now auro-portless.service >/dev/null 2>&1 || true
    sudo systemctl stop caddy.service >/dev/null 2>&1 || true
    sudo systemctl enable --now portless.service >/dev/null 2>&1 || true
  fi
}
trap rollback EXIT

sudo systemctl disable --now portless.service
legacy_stopped=1
"$script_dir/install_portless_service.sh" --apply
"$script_dir/install_caddy_linux.sh" --apply

systemctl --user is-active --quiet auro-portless.service
systemctl is-active --quiet caddy.service
if systemctl is-active --quiet portless.service; then
  echo "Legacy Portless service is still active after migration." >&2
  exit 1
fi
success=1
trap - EXIT

echo "Migrated legacy Linux Portless service to dotfiles-owned Portless plus Caddy."
