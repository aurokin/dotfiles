# Env for ALL koopa shells, including non-interactive ssh execs (sourced from
# ~/.zshenv). Interactive-only config stays in koopa.zsh.

# koopa actively develops diffwarden, tprompt, and agentscan and runs dev
# builds of each (diffwarden: pnpm link → ~/.local/bin; tprompt: go build →
# ~/.local/bin; agentscan: cargo install → ~/.cargo/bin). Keep mise from
# installing the released versions here, since mise-managed tool dirs are
# re-prepended ahead of those dirs and would shadow the dev builds.
export MISE_DISABLE_TOOLS="npm:diffwarden,github:aurokin/tprompt,github:aurokin/agentscan"
