# dotfiles

Configurations of my daily utils.

- Neovim

## Setup

Only the Neovim config is maintained right now. Other configs in this repo are stale and are not installed by the setup script.

```sh
./setup.sh
```

The script installs Neovim nightly and backs up an existing `~/.config/nvim` directory before replacing it with a symlink to this repo.

- Arch Linux: bootstraps `paru` when needed, then installs `neovim-git`.
- macOS and other Linux distributions: uses Homebrew to install Neovim HEAD.

Preview changes without writing:

```sh
./setup.sh --dry-run
```

Install only the config and skip package-manager work:

```sh
./setup.sh --skip-neovim-install
```
