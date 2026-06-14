# Host config for metapod (this Mac).

# Apple Python user installs land here when scripts use /usr/bin/python3 -m pip.
# Keep it after mise-managed tools so project/runtime Python shims win.
apple_python_user_bin="$HOME/Library/Python/3.9/bin"
if [[ -d "$apple_python_user_bin" ]]; then
  case ":$PATH:" in
    *":$apple_python_user_bin:"*) ;;
    *) export PATH="$PATH:$apple_python_user_bin" ;;
  esac
fi
unset apple_python_user_bin
