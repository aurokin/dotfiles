if command -v wt >/dev/null 2>&1; then
    eval "$(wt config shell init zsh 2>/dev/null || true)"
fi
