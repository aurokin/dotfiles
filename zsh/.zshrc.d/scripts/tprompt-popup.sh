#!/usr/bin/env bash
set -euo pipefail
# Bridge tmux display-popup to tprompt. Binary resolution (local cargo build vs
# mise shim) is shared via resolve-bin.sh so the popup does not depend on the
# tmux server's PATH.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/resolve-bin.sh"

exec "$(resolve_bin tprompt)" tui "$@"
