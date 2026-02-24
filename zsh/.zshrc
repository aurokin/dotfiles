# Auro's ZSH Config
# Requires Installing
# - Pure (https://github.com/sindresorhus/pure)

# Terminal
export TERM=xterm-256color

# NVim
export EDITOR=nvim
export VISUAL=nvim

# Git
export GIT_EDITOR=nvim

# Tree
export LS_COLORS=true

# Claude
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

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

# Pure
if [[ -n "$HOMEBREW_PREFIX" ]]; then
    fpath+=("$HOMEBREW_PREFIX/share/zsh/site-functions")
fi
autoload -U promptinit; promptinit
prompt pure
if [[ -n ${prompt_pure_state[username]-} ]]; then
    prompt_pure_state[username]='%F{243}%n%f%F{243}@%m%f'
fi

export PATH="$HOME/.bin:$HOME/.local/bin:$PATH"

# Set Aliases
alias c="clear"
alias cc="claude --dangerously-skip-permissions"
# Keep zsh/.zshrc.d/scripts/lgpt.sh in sync if this command changes.
alias gpt="codex --dangerously-bypass-approvals-and-sandbox"
alias lgpt="$HOME/.zshrc.d/scripts/lgpt.sh"
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
alias gws="$HOME/.zshrc.d/scripts/git-workspace.sh status"
alias gwp="$HOME/.zshrc.d/scripts/git-workspace.sh pull"
alias gcb="git checkout \$(git branch | fzf)"
alias lg="lazygit"
alias rr="rm -rf"
alias twm="source ~/.zshrc.d/scripts/twigsmux.sh"
alias agents="$HOME/.zshrc.d/scripts/find-agents-tmux.sh"
alias pscripts="$HOME/.zshrc.d/scripts/list-package-json-scripts.sh"

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
PC_NAME=$(uname -n)
HOST_FILE="$HOME/.zshrc.d/hosts/$PC_NAME.zsh"
KEYS_FILE="$HOME/.zshrc.d/keys.zsh"

if [[ -f "$HOST_FILE" ]]; then
    source "$HOST_FILE"
fi

if [[ -f "$KEYS_FILE" ]]; then
    source "$KEYS_FILE"
fi

if [[ -f "$HOME/.zshrc.d/scripts/tmux-reload.zsh" ]]; then
    source "$HOME/.zshrc.d/scripts/tmux-reload.zsh"
fi

# Mise
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
fi

# Zoxide
eval "$(zoxide init zsh)"
