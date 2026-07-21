# Env for ALL koopa shells, including non-interactive ssh execs (sourced from
# ~/.zshenv). Interactive-only config stays in koopa.zsh.

# koopa runs diffwarden as a pnpm-linked dev build (~/code/diffwarden via
# ~/.local/bin/diffwarden). Keep mise from installing the npm release here,
# since mise-managed tool dirs are re-prepended ahead of ~/.local/bin and
# would shadow the dev build.
export MISE_DISABLE_TOOLS="npm:diffwarden"
