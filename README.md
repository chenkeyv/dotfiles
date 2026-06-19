# dotfiles

Configurations of my daily utils.

- Neovim
- Zsh

## Setup

This repo currently maintains Neovim and Zsh configs.

```sh
./setup.sh
```

The script installs Neovim nightly, Zsh tooling, and backs up existing config files before replacing them with links to this repo.

- Arch Linux: bootstraps `paru` when needed, then installs `neovim-git`.
- macOS and other Linux distributions: uses Homebrew to install Neovim HEAD.
- Zsh: uses Starship for the prompt, Antidote for plugin management, and F-Sy-H for syntax highlighting.

Machine-local Zsh settings, including secrets, proxies, and host-specific paths,
belong in `~/.config/zsh/local.zsh`. That file is sourced by `.zshrc` and is
not tracked by this repo.

Preview changes without writing:

```sh
./setup.sh --dry-run
```

Install only the config and skip package-manager work:

```sh
./setup.sh --skip-neovim-install --skip-zsh-install
```
