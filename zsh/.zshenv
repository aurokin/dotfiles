# Sourced by EVERY zsh, including non-interactive `ssh <host> <cmd>` execs,
# which skip .zshrc entirely. It exists so remotely spawned tools (agentscan
# focus/hostname probes, scripts, cron) resolve the same host-specific
# binaries — notably Homebrew's tmux — as the interactive shells that start
# long-lived servers. Keep it tiny and fast: interactive setup belongs in
# .zshrc; host env that must also reach non-interactive shells belongs in
# ~/.zshrc.d/hosts/<short-hostname>.env.zsh (sourced below when present).
PC_NAME=$(uname -n)
PC_NAME=${PC_NAME%%.*}
HOST_ENV_FILE="$HOME/.zshrc.d/hosts/$PC_NAME.env.zsh"
if [[ -f "$HOST_ENV_FILE" ]]; then
  source "$HOST_ENV_FILE"
fi
unset PC_NAME HOST_ENV_FILE
