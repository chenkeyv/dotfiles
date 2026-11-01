# Codex Project Instructions

## Repository Context

- This repository maintains personal dotfiles for Neovim, Zsh, Starship, Ghostty, setup automation,
  an offline bundle builder, and Agent Toolbox setup for Codex.
- When the user asks to use Agent Toolbox, Agentbox, workflows, or specialist agents, use the
  installed Agent Toolbox plugin skill and follow its bundled workflow files.
- Current user instructions and current repository files take precedence over bundled Agent Toolbox
  memory templates.

## Working Rules

- Do not vendor or clone Agent Toolbox into this repository unless plugin installation is
  unavailable.
- Keep machine-local Zsh settings, secrets, proxies, and host-specific paths out of the repo; they
  belong in `~/.config/zsh/local.zsh`.
- Avoid committing secrets, credentials, OAuth state, or machine-local configuration.
- Keep setup changes idempotent: rerunning `setup.sh` should skip already-correct links, installed
  tools, and installed Codex plugins.
- When adding a language server or formatter to the Neovim config, add it to `editor_tools` in
  `setup.sh` too.
- Keep `nvim/nvim-pack-lock.json` committed, and commit it after updating plugins.

## Verification

- After editing `setup.sh`, run `bash -n setup.sh` and `shellcheck setup.sh`.
- After editing tracked Zsh files, run `zsh -n` on each changed file separately; given several files
  it checks only the first.
- After editing the Neovim config, run `make smoke`. Plain `nvim --headless` exits 0 on a broken config.
- For broad setup changes, run `./setup.sh --dry-run --skip-neovim-install --skip-zsh-install`.
- Run `make validate` for everything CI runs.
