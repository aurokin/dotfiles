#!/usr/bin/env bash
set -euo pipefail
# Bridge tmux display-popup to agentscan.
# tmux popups spawn a non-interactive shell without the user's
# interactive PATH, so resolve the binary explicitly here.
exec "$HOME/.cargo/bin/agentscan" tui "$@"
