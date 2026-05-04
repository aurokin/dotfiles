#!/usr/bin/env bash
set -euo pipefail
# Bridge tmux display-popup to agentscan.
# tmux popups inherit the tmux server PATH; keep ~/.cargo/bin before mise's
# released agentscan install while dogfooding unreleased local builds.
exec agentscan tui "$@"
