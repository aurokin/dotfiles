# Auro's ZSH Config
# Requires Installing
# - Pure (https://github.com/sindresorhus/pure)

# Pure
fpath+=($HOME/.zsh/pure)
autoload -U promptinit; promptinit
prompt pure

# Terminal
export TERM=xterm-256color

# NVim
export EDITOR=nvim
export VISUAL=nvim

# Git
export GIT_EDITOR=nvim

# Tree
export LS_COLORS=true

# Nix
export NIXPKGS_ALLOW_UNFREE=1

# LANG
export JDTLS_ENABLED=false;
export JDTLS_DIR="/usr/local/lib/jdtls"

# XDG
export XDG_CONFIG_HOME="$HOME/.config"

user=`id -un`
if [[ $OSTYPE == *"darwin"* ]]; then
    # OSX
    export OS="darwin";
    export GLOBAL_NODE_MODULES="/opt/homebrew/lib/node_modules"
    export PATH="/Users/$user/.nix-profile/bin:$PATH"
    export PATH="/opt/homebrew/bin:$PATH"
    export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
    export PATH="/opt/homebrew/lib/ruby/gems/3.3.0/bin:$PATH"
    export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
    export PATH="/nix/var/nix/profiles/default/bin:$PATH"
    export PATH="/Users/$user/.cargo/bin:$PATH"
    export PATH="/Users/$user/.bin:$PATH"
    export PATH="/Users/$user/.local/bin:$PATH"

    if [[ -d "/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home/bin" ]]; then
        export PATH="/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home/bin:$PATH" 
    fi
else
    export OS="unix"
    export GLOBAL_NODE_MODULES="/usr/lib/node_modules" 
    export PATH="/opt/swift/usr/bin:$PATH"
    export PATH="/nix/var/nix/profiles/default/bin:$PATH"
    export PATH="/home/$user/.nix-profile/bin:$PATH"
    export PATH="/home/$user/.cargo/bin:$PATH"
    export PATH="/home/$user/.bin:$PATH"
    export PATH="/home/$user/.local/bin:$PATH"
    export SUDO_EDITOR="/home/$user/.nix-profile/bin/nvim"
fi

# Set Aliases
alias c="clear"
alias e="exit"
alias ds="directory-sync"
alias lsl="eza -l"
alias lsa="eza -la"
alias lsz="eza"
alias ga="git add ."
alias gc="git commit"
alias gl="git log"
alias gs="git status"
alias gd="git diff"
alias gp="git push"
alias jdtls="export JDTLS_ENABLED=true"
alias gcb="git checkout \$(git branch | fzf)"
alias lg="lazygit"
alias rr="rm -rf"
alias twm="source ~/.zsh_scripts/twigsmux.sh"
alias zshrd="source ~/.zshrc"

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

# Load Local Alias
# If File Exists
PC_NAME=$(uname -n)
if [[ $PC_NAME == "bront" ]]; then
    source /home/auro/.bront.zsh  
elif [[ $PC_NAME == "L128392" ]]; then
    source /Users/hsadler/.L128392.zsh
elif [[ $PC_NAME == "luma" ]]; then
    source $HOME/.luma.zsh
fi

# Zoxide
eval "$(zoxide init zsh)"
