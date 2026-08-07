# Interactive-only host config for Herb (CachyOS retro/dev desktop).

# Grok is installed outside mise. The shared zshrc already appends ~/.grok/bin
# without shadowing Cursor Agent's `agent`; keep only completions here.
grok_completions="$HOME/.grok/completions/zsh"
if [[ -d "$grok_completions" ]]; then
  case " ${fpath[*]} " in
    *" $grok_completions "*) ;;
    *) fpath=("$grok_completions" $fpath) ;;
  esac
  autoload -Uz compinit
  compinit -C
fi
unset grok_completions
