# Host config for metapod (this Mac).

if [[ -n "${METAPOD_HOST_ZSH_LOADED:-}" ]]; then
  return 0
fi
export METAPOD_HOST_ZSH_LOADED=1

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

# N64 agent workspace.
export N64_WORKSPACE="$HOME/code"
export PARALLEL_N64_REPO="$N64_WORKSPACE/parallel-n64"
export RETROARCH_REPO="$N64_WORKSPACE/RetroArch"
# 2026-07-02: point at the MoltenVK 1.4.1 app copy. The /Applications app
# bundles MoltenVK 1.2.8, which renders black with the parallel core in
# hi-res (the 2026-07-02 black-capture incident); the MVK141 app copy is
# refreshed by parallel-n64 tools/adapters/build_retroarch_agent_control_macos.sh.
export RETROARCH_BIN="$PARALLEL_N64_REPO/artifacts/external/RetroArch-MVK141.app/Contents/MacOS/RetroArch"
export RETROARCH_BASE_CONFIG="$RETROARCH_REPO/retroarch.cfg"
export BASE_CONFIG="$RETROARCH_BASE_CONFIG"
export PARALLEL_N64_CORE="$PARALLEL_N64_REPO/parallel_n64_libretro.dylib"
export CORE_PATH="$PARALLEL_N64_CORE"
export PAPER_MARIO_ROM="$PARALLEL_N64_REPO/assets/Paper Mario (USA).zip"
export ROM_PATH="$PAPER_MARIO_ROM"
export PARALLEL_N64_AGENT_APPEND_CONFIG="$HOME/.config/retroarch/parallel-n64-agent.append.cfg"
export N64_RUN_ROOT="$PARALLEL_N64_REPO/artifacts/local-runs"
