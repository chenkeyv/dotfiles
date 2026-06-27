# dotfiles

Configurations of my daily utils.

- Neovim
- Zsh
- Agent Toolbox for Codex
- ShellCheck validation

## Setup

This repo currently maintains Neovim and Zsh configs, plus Agent Toolbox setup for Codex.

```sh
./setup.sh
```

The script installs Neovim nightly, Zsh tooling, Agent Toolbox for Codex, and
backs up existing config files before replacing them with links to this repo.
It is safe to rerun; existing links and installed Agent Toolbox plugins are
detected and skipped.

- Arch Linux: bootstraps `paru` when needed, then installs `neovim-git`.
- macOS and other Linux distributions: uses Homebrew to install Neovim HEAD.
- Zsh: uses Starship for the prompt, Antidote for plugin management, and F-Sy-H for syntax
  highlighting.
- Shell scripts: installs ShellCheck for local validation.
- Agent Toolbox: uses `codex plugin marketplace add chenkeyv/agent-toolbox --ref main`, then installs
  `agent-toolbox@agent-toolbox`.

Machine-local Zsh settings, including secrets, proxies, and host-specific paths,
belong in `~/.config/zsh/local.zsh`. That file is sourced by `.zshrc` and is
not tracked by this repo.

Preview changes without writing:

```sh
./setup.sh --dry-run
```

Install only the config links and skip install/update work:

```sh
./setup.sh --skip-neovim-install --skip-zsh-install --skip-agent-toolbox-install
```

Skip Agent Toolbox installation:

```sh
./setup.sh --skip-agent-toolbox-install
```

## Validation

```sh
bash -n setup.sh
shellcheck setup.sh
zsh -n zsh/zshenv zsh/zprofile zsh/zshrc
```
