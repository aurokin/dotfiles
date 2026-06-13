#!/bin/bash

set -euo pipefail

if ! command -v mise >/dev/null 2>&1; then
  echo "mise not found. Install it first (dot_scripts/brew_install.sh installs it on macOS)." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# This script expects tools to be declared in ~/.config/mise/config.toml (stowed from this repo).
mise install -y
mise upgrade -y

# Ruby-backed gem tools can retain native extensions linked against an older
# Ruby patch release after `ruby = "latest"` advances, so rebuild them
# against the currently active Ruby.
mise install --force -y gem:cocoapods gem:fastlane

# Load the mise environment for this script (so the checks below resolve the mise-managed tools).
eval "$(mise env -s bash)"

# Direct vendor installers target ~/.local/bin and ~/.grok/bin; keep them ahead
# of Homebrew here so freshly installed tools resolve during this script.
export PATH="$HOME/.grok/bin:$HOME/.local/bin:$PATH"

# Optional: enable package-manager shims for Node.
if command -v corepack >/dev/null 2>&1; then
  corepack enable || true
fi

# AI coding clients managed by their upstream direct installers, not Homebrew or
# mise. This is separate from desktop app casks such as Claude, Codex, and
# Antigravity.
echo "Installing/updating Codex CLI..."
curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=true sh

echo "Installing/updating Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

echo "Installing/updating Cursor Agent..."
curl -fsSL https://cursor.com/install | bash

echo "Installing/updating Antigravity CLI..."
curl -fsSL https://antigravity.google/cli/install.sh | bash

# The Antigravity bootstrapper currently appends its own PATH block even when
# ~/.local/bin is already active. Dotfiles own PATH setup, so remove only that
# exact installer block if it was added.
remove_antigravity_path_block() {
  local profile="$1"
  [[ -e "$profile" ]] || return 0

  local profile_target
  profile_target="$profile"
  if [[ -L "$profile" ]]; then
    profile_target="$(readlink "$profile")"
    if [[ "$profile_target" != /* ]]; then
      profile_target="$(cd "$(dirname "$profile")" >/dev/null 2>&1 && pwd -P)/$profile_target"
    fi
  fi
  [[ -f "$profile_target" ]] || return 0

  local tmp path_line
  tmp="$(mktemp)"
  path_line="export PATH=\"$HOME/.local/bin:\$PATH\""

  awk -v path_line="$path_line" '
    $0 == "# Added by Antigravity CLI installer" {
      if ((getline nextline) > 0) {
        if (nextline == path_line) {
          next
        }
        print
        print nextline
        next
      }
    }
    { print }
  ' "$profile_target" >"$tmp"

  if cmp -s "$profile_target" "$tmp"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$profile_target"
  fi
}

remove_antigravity_path_block "$HOME/.zshrc"
remove_antigravity_path_block "$HOME/.zprofile"
remove_antigravity_path_block "$HOME/.profile"

echo "Installing/updating Grok Build..."
curl -fsSL https://x.ai/cli/install.sh | SHELL=/usr/bin/false bash

opencode_postinstall="$HOME/.local/share/mise/installs/npm-opencode-ai/latest/lib/node_modules/opencode-ai/postinstall.mjs"
if command -v opencode >/dev/null 2>&1 && ! opencode --version >/dev/null 2>&1 && [[ -f "$opencode_postinstall" ]]; then
  echo "Running opencode-ai postinstall..."
  (cd "$(dirname "$opencode_postinstall")" && node postinstall.mjs)
fi

# agent-browser needs its own post-install step in addition to the npm CLI package.
if command -v agent-browser >/dev/null 2>&1; then
  agent-browser install
fi

mise reshim

short_hostname="$(uname -n)"
short_hostname="${short_hostname%%.*}"

if [[ "$short_hostname" == "koopa" || "$short_hostname" == "luma" ]]; then
  # This helper lives beside this script; the LAN service refresh is best-effort.
  if ! "$script_dir/portless_service_install.sh"; then
    echo "Warning: Portless launchd service refresh failed; continuing runtime tool install." >&2
  fi
fi

echo "Resolved tools:"
command -v opencode codex claude cursor-agent agy grok agent agent-browser portless prettierd pod fastlane beautysh http httpie ranger gemini copilot || true

echo "Tool versions:"
opencode --version || true
codex --version || true
claude --version || true
cursor-agent --version || true
agy --version || true
grok --version || true
agent-browser --version || true
portless --version || true
prettierd --version || true
gemini --version || true
copilot --version || true
pod --version || true
fastlane --version || true
beautysh --version || true
http --version || true
ranger --version || true
