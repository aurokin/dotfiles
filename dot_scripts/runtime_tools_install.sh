#!/bin/bash

set -euo pipefail

if ! command -v mise >/dev/null 2>&1; then
  echo "mise not found. Install it first (dot_scripts/brew_install.sh installs it on macOS)." >&2
  exit 1
fi

# This script expects tools to be declared in ~/.config/mise/config.toml (stowed from this repo).
mise install -y
mise upgrade -y

# Load the mise environment for this script (so the checks below resolve the mise-managed tools).
eval "$(mise env -s bash)"

# Optional: enable package-manager shims for Node.
if command -v corepack >/dev/null 2>&1; then
  corepack enable || true
fi

# Claude Code is installed via the upstream native installer when missing.
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

mise reshim

echo "Resolved tools:"
command -v opencode claude prettierd pod fastlane beautysh http httpie ranger gemini copilot || true

echo "Tool versions:"
opencode --version || true
claude --version || true
prettierd --version || true
gemini --version || true
copilot --version || true
pod --version || true
fastlane --version || true
beautysh --version || true
http --version || true
ranger --version || true
