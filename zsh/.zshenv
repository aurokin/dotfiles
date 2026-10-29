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

# Agents and SSH execs need the same scoped wrappers as interactive shells.
# This file defines functions and credential references only; it does not
# fetch secrets or authenticate. The executable also serves bash/other shells.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
if [[ -f "$HOME/.zshrc.d/secrets.zsh" ]]; then
  source "$HOME/.zshrc.d/secrets.zsh"
fi
