#!/usr/bin/env bash
set -euo pipefail
# Bridge tmux display-popup to tprompt.
#
# Prefer ~/.cargo/bin/tprompt when present so local dev builds win for
# dogfooding. Fall back to mise's shim for the released install. Both are
# addressed by absolute path so the popup does not depend on the tmux server's
# PATH or on shell activation.
if [[ -x "$HOME/.cargo/bin/tprompt" ]]; then
  exec "$HOME/.cargo/bin/tprompt" tui "$@"
fi
exec "$HOME/.local/share/mise/shims/tprompt" tui "$@"
