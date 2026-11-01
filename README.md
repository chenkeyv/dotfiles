# dotfiles

[![CI][ci-badge]][ci]

Configurations of my daily utils.

- Neovim, with its language servers, formatters, and pinned plugins
- Zsh
- Ghostty
- Declared Codex plugins and standalone skills
- ShellCheck validation
- Offline bundle builder for GitHub Actions artifacts

## Setup

This repo currently maintains Neovim, Zsh, and Ghostty configs, uv-managed user-level Python, Node.js with
pnpm, and declarative Codex plugin and skill lists.

```sh
./setup.sh
```

In an interactive terminal, setup opens with a brief cyan sweep and shows numbered phases
with a total elapsed time. Installer output and prompts stay visible. Redirected output, CI,
`TERM=dumb`, and `NO_COLOR=1` use plain text. Use `./setup.sh --no-animation` to opt out,
or `./setup.sh --dry-run` to preview the presentation and planned actions without changing files.

The script first backs up existing config files and replaces them with links to this repo. It then
installs Neovim nightly, Zsh tooling, uv with Python 3.14 as the user-level default, Node.js with pnpm
for JavaScript dependencies, the language servers and formatters Neovim uses, the Maple Mono NF font,
and the plugins and skills declared in `codex-packages.json`. Config links remain installed if a later
installation fails; fix the reported error and rerun to finish installing tools. It is safe to rerun:
existing links, plugins, and skills are detected and skipped, and a tool is installed only when its
command is missing from `PATH`, so setup does not upgrade tools you already have.

On a new Mac, the Homebrew installer asks for your password and a confirmation. Without a terminal, it
runs non-interactively and needs passwordless or cached `sudo`.

After setup, load the configuration in the current terminal:

```sh
exec zsh -l
```

Setup leaves the current shell process and your default login shell unchanged. If new terminals
still open Bash or another shell, configure your terminal or account to launch Zsh. Starship and
Antidote must be installed successfully for the prompt and plugins to appear.

- Arch Linux: bootstraps `paru` when needed, then installs `neovim-git`.
- macOS and other Linux distributions: uses Homebrew to install Neovim HEAD.
- Zsh: uses Starship for the prompt, Antidote for plugin management, and F-Sy-H for syntax
  highlighting.
- Ghostty: links `ghostty/config` to `${XDG_CONFIG_HOME:-~/.config}/ghostty/config`, backing up an
  existing config before replacing it. Installs the configured Maple Mono NF font through Homebrew
  (`font-maple-mono-nf`) on macOS and other Linux distributions, or `paru`
  (`maplemono-nf-unhinted`) on Arch Linux. Install Ghostty 1.3+ separately.
  The config uses a transparent background, command-finished notifications, and a bottom Quick
  Terminal opened with `Alt+Space` on the display under the mouse pointer.
- Python: installs uv through Homebrew or `paru`, then exposes uv-managed Python 3.14 as `python`
  and `python3` through `~/.local/bin`. The operating system Python remains unchanged.
- Node.js: installs Node.js and pnpm through Homebrew or `paru`; use pnpm for project dependency
  installation and lockfiles.
- Editor tools: installs the `tree-sitter` CLI, language servers, and formatters listed in
  `editor_tools` in `setup.sh`. `sourcekit-lsp` and `swift` come with Xcode or the Swift toolchain.
  On Arch Linux, TypeScript comes from pnpm because the Arch package predates `tsc --lsp`.
- Neovim plugins: `nvim/nvim-pack-lock.json` is tracked, so a new machine installs the same plugin
  revisions. Commit it after `vim.pack.update()`. Tree-sitter parsers are limited to the languages
  listed in `nvim/lua/plugins/treesitter.lua`; add a language there to get its parser.
- SkillHub: when a configured skill uses the `skillhub` installer, setup installs the CLI through the
  upstream `--cli-only` bootstrap, then installs the skill into `~/.agents/skills`.
- Codex plugins: installs `PLUGIN@MARKETPLACE` selectors from the `plugins` array. Bundled and
  runtime marketplaces are supplied by Codex. For `@personal` plugins, setup preserves unrelated
  entries in `~/.agents/plugins/marketplace.json` and adds a Git-backed entry to the personal
  marketplace. A plugin that fails does not block the rest, but setup still exits non-zero. Without the
  Codex CLI, setup skips plugins with a warning. The list holds plugins that work from Codex alone;
  account connectors such as Gmail or GitHub need sign-in and stay out of this repo.
- Standalone skills: the `skills` array records each skill's name, installer, and any required
  reference. Local-only entries are inventoried but cannot be recreated when their
  source directory is absent.
- Shell scripts: installs ShellCheck for local validation.
- Surge: when selected and `/Applications/Surge.app/Contents/Resources/Skills/surge` is available,
  links it to
  `$CODEX_HOME/skills/surge` (or `~/.codex/skills/surge` by default) so the skill stays current with
  Surge app updates.

## Offline Bundle

The Go command under `cmd/dotfiles` is only used to build GitHub Actions artifacts. It is not
installed by `setup.sh`.

The daily workflow builds a single multi-call payload for constrained environments:

```sh
go build -trimpath -o /tmp/dotfiles-pack ./cmd/dotfiles
/tmp/dotfiles-pack pack -o cmd/dotfiles/payload
CGO_ENABLED=0 go build -tags embedded -trimpath -o dotfiles-env ./cmd/dotfiles
rm -rf cmd/dotfiles/payload
./dotfiles-env list
./dotfiles-env apply
```

The bundle artifact is a Go binary with the payload embedded through Go's `embed` package, so it
does not require `tar`, `base64`, network access, or sudo on the target host. Daily GitHub Actions
builds publish native artifacts for `linux-amd64`, `darwin-arm64`, and `darwin-amd64`, kept for 7 days.
Each artifact includes the dotfiles payload plus portable user-space tools downloaded by
`scripts/fetch-tools.sh`, including the latest Neovim nightly for that platform from the daily workflow
run. The payload includes the Ghostty config, and `apply` installs it alongside the shell and editor
configs.

Each artifact also carries what the configs would otherwise download: Neovim plugins at their locked
revisions, compiled Tree-sitter parsers, blink.cmp's fuzzy library, antidote, and the Zsh plugins.
`apply` unpacks these under `~/.local/share` once per bundle build, replacing `nvim/site` and backing up
the old copy unless `--force` is given. The workflow checks each artifact with Git network access
blocked. Zsh itself and language servers are not included, so editing works offline without LSP unless
the host provides the servers.

To build a bundle locally, on a host that matches the target:

```sh
scripts/fetch-tools.sh darwin-arm64 dist/tools/darwin-arm64 dist/data/darwin-arm64
go build -trimpath -o /tmp/dotfiles-pack ./cmd/dotfiles
/tmp/dotfiles-pack pack --tools-dir dist/tools/darwin-arm64 --data-dir dist/data/darwin-arm64 \
  -o cmd/dotfiles/payload
CGO_ENABLED=0 go build -tags embedded -trimpath -o dotfiles-env ./cmd/dotfiles
rm -rf cmd/dotfiles/payload
scripts/nvim-smoke.sh --home <home-after-apply>
```

On an offline host:

```sh
chmod +x dotfiles-env-linux-amd64
./dotfiles-env-linux-amd64 apply
./dotfiles-env-linux-amd64 tool list
./dotfiles-env-linux-amd64 tool nvim --version
./dotfiles-env-linux-amd64 tool rg --version
```

Machine-local Zsh settings, including secrets, proxies, and host-specific paths,
belong in `~/.config/zsh/local.zsh`. That file is sourced by `.zshrc` and is
not tracked by this repo.

Preview changes without writing:

```sh
./setup.sh --dry-run
```

Install only the config links and skip install/update work:

```sh
./setup.sh --skip-neovim-install --skip-zsh-install --skip-python-install \
  --skip-node-install --skip-editor-tools-install --skip-skillhub-install \
  --skip-skill-install --skip-plugin-install --skip-font-install
```

Skip uv and user-level Python installation:

```sh
./setup.sh --skip-python-install
```

Skip Node.js and pnpm installation:

```sh
./setup.sh --skip-node-install
```

Skip language servers, formatters, and the `tree-sitter` CLI:

```sh
./setup.sh --skip-editor-tools-install
```

Refuse to bootstrap the SkillHub CLI, even if a configured skill needs it:

```sh
./setup.sh --skip-skillhub-install
```

Skip Maple Mono NF font installation:

```sh
./setup.sh --skip-font-install
```

Choose the Codex plugins and standalone skills installed by normal setup in the single
`codex-packages.json` file:

```json
{
  "version": 1,
  "plugins": [
    "browser@openai-bundled"
  ],
  "skills": [
    {
      "name": "example-skill",
      "installer": "skillhub",
      "reference": "@example-team/example-skill"
    },
    {
      "name": "surge",
      "installer": "app"
    }
  ]
}
```

The schema version is currently `1`. Plugin entries use `PLUGIN@MARKETPLACE`. Skill installers are
`skillhub`, `app` for Surge, and `local` for an inventory-only skill already available on a machine.
A string skill entry is shorthand for a SkillHub reference.

Use `--packages-file` to select a different JSON file. You can also add entries for one setup run by
repeating `--skill` or `--plugin`:

```sh
./setup.sh --packages-file ~/.config/dotfiles/codex-packages.json
./setup.sh --skill example-skill --plugin browser@openai-bundled
```

Setup skips valid SkillHub skills already present in `~/.agents/skills`, the legacy
`$CODEX_HOME/skills` directory, or SkillHub's install record. Surge is checked against the
authoritative application-bundle symlink.
The checked-in JSON declares the plugins and standalone skills managed by setup.
To skip either category for one setup run:

```sh
./setup.sh --skip-skill-install
./setup.sh --skip-plugin-install
```

## Tooling Decisions

- [agnix evaluation](docs/decisions/agnix.md): keep the dependency out of the managed setup for
  now; reconsider a pinned CLI-only trial if its diagnostics become necessary.

## Validation

CI runs the same checks as this command, which needs Neovim nightly, Go, Python, Zsh, and ShellCheck:

```sh
make validate
```

To check only that the Neovim config loads, run `make smoke`. It clones the plugins at their locked
revisions into a temporary directory and asserts on the loaded state, because plain `nvim --headless`
exits 0 even when `init.lua` raises an error.

To syntax-check Zsh files by hand, run `zsh -n` once per file. Given several files, it checks only the
first and treats the others as script arguments.

[ci]: https://github.com/chenkeyv/dotfiles/actions/workflows/ci.yml
[ci-badge]: https://github.com/chenkeyv/dotfiles/actions/workflows/ci.yml/badge.svg
