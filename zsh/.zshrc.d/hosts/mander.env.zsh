# Env for ALL mander shells, including non-interactive ssh execs (sourced from
# ~/.zshenv). Interactive-only config stays in mander.zsh.

# Linuxbrew tools must outrank the apt versions for every entrypoint: the tmux
# server on this VM runs brew's tmux, and a fresh /usr/bin/tmux 3.4 client is
# dropped by the 3.6b server with "server exited unexpectedly" — which is what
# broke agentscan focus and hostname probes arriving over non-interactive SSH.
linuxbrew_bin="/home/linuxbrew/.linuxbrew/bin"
if [[ -d "$linuxbrew_bin" ]]; then
  case ":$PATH:" in
    *":$linuxbrew_bin:"*) ;;
    *) export PATH="$linuxbrew_bin:$PATH" ;;
  esac
fi
unset linuxbrew_bin
