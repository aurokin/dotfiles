# Host config for koopa (this Mac). Keyed on the short hostname (see the
# PC_NAME normalization in ~/.zshrc), so it survives macOS hostname drift
# between koopa.local / koopa.home.arpa / koopa.

# Bun global bin (for `bun add -g` packages like ccusage, ccusage-codex).
# Keep it lower priority than mise-managed tools.
bun_global_bin="$HOME/.bun/bin"
if [[ -d "$bun_global_bin" ]]; then
  case ":$PATH:" in
    *":$bun_global_bin:"*) ;;
    *) export PATH="$PATH:$bun_global_bin" ;;
  esac
fi

# Grok CLI installed outside mise (~/.grok/bin holds the `grok`/`agent`
# symlinks). Replaces the unguarded prepend the grok installer appends to
# ~/.zshrc; idempotent so re-sourcing doesn't stack PATH entries.
grok_bin="$HOME/.grok/bin"
if [[ -d "$grok_bin" ]]; then
  case ":$PATH:" in
    *":$grok_bin:"*) ;;
    *) export PATH="$grok_bin:$PATH" ;;
  esac
fi

# Portless defaults for this always-home Mac. This is a non-secret preference,
# so it belongs in the host-specific zsh file rather than keys/private files.
# PORTLESS_LAN=1 makes manual proxy starts default to mDNS/LAN mode; the
# launchd service is installed in LAN mode by dot_scripts/portless_service_install.sh.
export PORTLESS_LAN=1
