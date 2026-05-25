#!/usr/bin/env bash
set -euo pipefail

if [[ -x "$HOME/.cargo/bin/agentscan" ]]; then
  exec "$HOME/.cargo/bin/agentscan" "$@"
fi

exec "$HOME/.local/share/mise/shims/agentscan" "$@"
