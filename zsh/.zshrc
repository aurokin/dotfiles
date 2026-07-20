# Auro's ZSH Config
# Requires Installing
# - Starship (https://starship.rs)

# Terminal
# Let terminal emulators and tmux set TERM themselves when possible. tmux panes
# need a tmux/screen TERM so TUIs use the right terminfo. SSH can forward newer
# terminal names (for example, xterm-ghostty) to hosts that do not have that
# terminfo entry yet; fall back before curses/tmux clients start.
if [[ -n "${TMUX:-}" && "$TERM" != tmux-* && "$TERM" != screen-* ]]; then
    export TERM=tmux-256color
elif [[ -z "${TMUX:-}" ]]; then
    if [[ -z "${TERM:-}" || "$TERM" == "dumb" ]]; then
        export TERM=xterm-256color
    elif ! infocmp "$TERM" >/dev/null 2>&1; then
        export TERM=xterm-256color
    fi
fi

# NVim
export EDITOR=nvim
export VISUAL=nvim

# Git
export GIT_EDITOR=nvim

# Tree
export LS_COLORS=true

# OpenCode
# Don't load Claude-scoped skills from ~/.claude/skills into OpenCode; skm
# places agent-scoped skills there (e.g. drive-codex) for Claude Code only.
export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1

# XDG
export XDG_CONFIG_HOME="$HOME/.config"

if [[ $OSTYPE == *"darwin"* ]]; then
    # OSX
    export OS="darwin"
    brew_bin="/opt/homebrew/bin/brew"
else
    export OS="unix"
    brew_bin="/home/linuxbrew/.linuxbrew/bin/brew"
    export PATH="/opt/swift/usr/bin:$PATH"
    export SUDO_EDITOR="nvim"
fi

if [[ -x "$brew_bin" ]]; then
    eval "$("$brew_bin" shellenv)"
elif command -v brew >/dev/null 2>&1; then
    eval "$(brew shellenv)"
fi

# Starship
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# Prepend user-local install dirs (some installers, e.g. Antigravity CLI, drop
# binaries in ~/.local/bin). This runs before `mise activate`, so it is captured in
# mise's __MISE_ORIG_PATH. Note: it does NOT beat mise-managed tools — mise's hook
# re-prepends its own tool dirs ahead of these on every cd.
export PATH="$HOME/.bin:$HOME/.local/bin:$PATH"

# Set Aliases
alias c="clear"
alias icat="kitten icat"
# Keep zsh/.zshrc.d/scripts/lcc.sh in sync if this command changes.
alias cc="claude --dangerously-skip-permissions"
alias super-claude="$HOME/.zshrc.d/scripts/super-claude"
alias scc="$HOME/.zshrc.d/scripts/super-claude --dangerously-skip-permissions"
alias super-claude-menu="$HOME/.zshrc.d/scripts/super-claude-menu"
alias sccm="$HOME/.zshrc.d/scripts/super-claude-menu --dangerously-skip-permissions"
alias ca="cursor-agent --force"
alias lcc="$HOME/.zshrc.d/scripts/lcc.sh"
alias lccr="LCC_FORK_SESSION=1 $HOME/.zshrc.d/scripts/lcc.sh"
alias lscc="CLAUDE_HOME=$HOME/.super-claude LCC_RUNNER_PATH=$HOME/.zshrc.d/scripts/super-claude LCC_DANGEROUS=1 $HOME/.zshrc.d/scripts/lcc.sh"
# Keep zsh/.zshrc.d/scripts/lgpt.sh in sync if this command changes.
alias gpt="codex --dangerously-bypass-approvals-and-sandbox"
alias lgpt="$HOME/.zshrc.d/scripts/lgpt.sh"
alias golo="gemini --yolo"
alias colo="copilot --yolo"
alias oc="opencode"
alias e="exit"
alias ds="directory-sync"
alias lsl="eza -lg --smart-group"
alias lsa="eza -lag --smart-group"
alias lsz="eza"
alias ga="git add ."
alias gc="git commit"
alias gl="git log"
alias gs="git status"
alias gd="git diff"
alias gp="git push"
alias gwss="trunkyard status"
alias gwp="trunkyard pull"
alias gwt="trunkyard new"
alias wts="wt switch"
alias wtc="wt switch --create --base=@"
alias wtr="wt remove"
alias gcb="git checkout \$(git branch | fzf)"
alias lg="lazygit"
alias rr="rm -rf"
alias agents="$HOME/.zshrc.d/scripts/agentscan.sh"
alias pscripts="$HOME/.zshrc.d/scripts/list-package-json-scripts.sh"
# macOS only
alias yawn="pmset displaysleepnow"
alias oyawn="oled-yawn sleep AW3225QF --yes"

# Bat Tokyo Night
export BAT_THEME="tokyonight_night"

# FZF Tokyo Night
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
--color=fg:#c0caf5,bg:#1a1b26,hl:#ff9e64 \
--color=fg+:#c0caf5,bg+:#292e42,hl+:#ff9e64 \
--color=info:#7aa2f7,prompt:#7dcfff,pointer:#7dcfff \
--color=marker:#9ece6a,spinner:#9ece6a,header:#9ece6a"

# FZF CD Alias
# Hidden Folders are also an issue
# For below to work we need to filter out library files or others we don't have perms to
alias fwd="cd \$(find /home /pluto /MURF /Users ~ ~/downloads ~/workspace ~/Downloads ~/roms ~/notes ~/code ~/images -mindepth 1 -maxdepth 1 -type d | fzf) && clear"
alias fcd="cd \$(find * -type d | fzf)"
# alias frd="cd / && cd \$(find * -typed | fzf)"

# Load Host Config
# Short hostname only - macOS reports koopa.local / koopa.home.arpa / koopa
# depending on the network, so strip any domain to keep host files stable.
PC_NAME=$(uname -n)
PC_NAME=${PC_NAME%%.*}
HOST_FILE="$HOME/.zshrc.d/hosts/$PC_NAME.zsh"
KEYS_FILE="$HOME/.zshrc.d/keys.zsh"

if [[ -f "$HOST_FILE" ]]; then
    source "$HOST_FILE"
fi

# Legacy: fleet hosts no longer have keys.zsh (P2 scoped-secrets migration),
# but non-fleet machines (work) still use this pattern — keep loading if present.
if [[ -f "$KEYS_FILE" ]]; then
    source "$KEYS_FILE"
fi

# Scoped secret wrappers (Proton Pass) — replaces keys.zsh (dotfiles-private v2 P2)
if [[ -f "$HOME/.zshrc.d/secrets.zsh" ]]; then
    source "$HOME/.zshrc.d/secrets.zsh"
fi

if [[ -f "$HOME/.zshrc.d/scripts/tmux-reload.zsh" ]]; then
    source "$HOME/.zshrc.d/scripts/tmux-reload.zsh"
fi

if [[ -f "$HOME/.zshrc.d/worktrunk.zsh" ]]; then
    source "$HOME/.zshrc.d/worktrunk.zsh"
fi

# twigsmux plugin shell integration (wtct / wtrt / twm); keybinds come from TPM.
if [[ -f "$HOME/.tmux/plugins/twigsmux/shell/init.zsh" ]]; then
    source "$HOME/.tmux/plugins/twigsmux/shell/init.zsh"
fi

# Mise
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
fi

# Zoxide
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"

    # whence -p, not command -v: secrets.zsh defines a zdr wrapper FUNCTION on
    # every host, so command -v passes even where the real binary is absent
    # (verified: "secrets: zdr executable not found" at login on luma).
    if whence -p zdr >/dev/null 2>&1; then
        eval "$(zdr init zsh)"
    fi
fi

# Grok CLI installs outside mise. Keep it after ~/.local/bin so Cursor Agent's
# `agent` symlink remains the default `agent` command.
grok_bin="$HOME/.grok/bin"
if [[ -d "$grok_bin" ]]; then
    case ":$PATH:" in
        *":$grok_bin:"*) ;;
        *) export PATH="$PATH:$grok_bin" ;;
    esac
fi
