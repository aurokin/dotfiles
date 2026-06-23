# Host config for haste (CachyOS/Linux gaming PC). Keyed on the short hostname
# (see PC_NAME normalization in ~/.zshrc), so interactive-only local installer
# setup stays off shared/global zsh config.

path_prepend_once() {
  local path_entry="$1"
  [[ -d "$path_entry" ]] || return 0
  case ":$PATH:" in
    *":$path_entry:"*) ;;
    *) export PATH="$path_entry:$PATH" ;;
  esac
}

# Some local vendor installers, including Antigravity CLI, drop binaries here.
# Global ~/.zshrc already includes ~/.local/bin, but keep this host file as the
# place to absorb installer-added Haste-only snippets without dirtying zshrc.
# Antigravity's CLI binary is ~/.local/bin/agy.
path_prepend_once "$HOME/.local/bin"

# Convenience aliases for the Antigravity CLI binary name. Diffwarden uses `agy`
# directly; these are for interactive shells where "antigravity" is easier to remember.
if [[ -x "$HOME/.local/bin/agy" ]]; then
  alias antigravity="$HOME/.local/bin/agy"
  alias anti-gravity="$HOME/.local/bin/agy"
fi

# Grok CLI installed outside mise (~/.grok/bin holds grok/agent symlinks and
# completions). This replaces the unguarded block the Grok installer appends to
# ~/.zshrc and is idempotent for re-sourcing.
grok_bin="$HOME/.grok/bin"
if [[ -d "$grok_bin" ]]; then
  path_prepend_once "$grok_bin"
fi

# Grok zsh completions, also installed outside mise.
grok_completions="$HOME/.grok/completions/zsh"
if [[ -d "$grok_completions" ]]; then
  case " ${fpath[*]} " in
    *" $grok_completions "*) ;;
    *) fpath=("$grok_completions" $fpath) ;;
  esac
  autoload -Uz compinit
  compinit -C
fi

unset -f path_prepend_once
unset grok_bin grok_completions
