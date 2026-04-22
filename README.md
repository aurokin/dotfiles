# Dotfiles
- Font: Roboto Condensed Mono Nerd Font
- OSX Keybinds: Karabiner Elements
- OSX Window Manager: Amethyst
- Shell: Zsh (Pure Prompt)
- Terminal: Alacritty
- Text Editor: Neovim
- Theme: Tokyo Night
- Tmux Session Management: twigsmux (.zshrc.d/scripts/twigsmux.sh && .tmux.conf && neovim config)

### Utilities
- bat
- btop
- delta
- eza
- fd
- fzf
- httpie
- ranger
- ripgrep
- stow
- tmux
- tree
- wget
- zoxide

### Git Worktrees
- `gws <path>` shows workspace git status across repos under a parent directory.
- `gwp <path>` pulls repos discovered by `gws`.
- `gwt <branch>` creates a centralized worktree at `~/worktrees/<project>/<branch>`, using `^` in paths for branch names that include `/`.
- Full repo-specific worktree documentation: [docs/git-worktrees.md](/Users/auro/.dotfiles/docs/git-worktrees.md)

### References
- Neovim Config: https://github.com/nvim-lua/kickstart.nvim
- Dotfiles: https://dr563105.github.io/blog/manage-dotfiles-with-gnu-stow/

> ## If you are starting your own dotfiles I recommend using these as a reference rather than as your own configuration.
