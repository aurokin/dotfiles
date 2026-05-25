#!/usr/bin/env bash
set -euo pipefail
# Bridge tmux display-popup to agentscan.
#
# Resolve through the shared wrapper so popup and direct hotkeys use the same
# binary preference without depending on the tmux server's PATH.
exec "$HOME/.zshrc.d/scripts/agentscan.sh" tui "$@"
