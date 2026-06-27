#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: ./setup.sh [--dry-run] [--copy] [--force]
                  [--skip-neovim-install] [--skip-zsh-install]
                  [--skip-agent-toolbox-install]

Installs the currently maintained dotfiles.

By default this installs Neovim HEAD/nightly, Zsh tooling, Agent Toolbox for
Codex, and links:
  ~/.config/nvim       -> <repo>/nvim
  ~/.zshenv            -> <repo>/zsh/zshenv
  ~/.zprofile          -> <repo>/zsh/zprofile
  ~/.zshrc             -> <repo>/zsh/zshrc
  ~/.config/zsh/.zshenv -> <repo>/zsh/zshenv
  ~/.config/zsh/.zprofile -> <repo>/zsh/zprofile
  ~/.config/zsh/.zshrc -> <repo>/zsh/zshrc
  ~/.config/zsh/plugins.txt -> <repo>/zsh/plugins.txt
  ~/.config/zsh/plugins-late.txt -> <repo>/zsh/plugins-late.txt
  ~/.config/starship.toml -> <repo>/starship/starship.toml

On Arch Linux, this bootstraps paru when needed and installs neovim-git.
On macOS and other Linux distributions, this installs Homebrew when needed and
uses it to install Neovim HEAD.

Options:
  --dry-run              Print the actions without changing files.
  --copy                 Copy nvim instead of creating a symlink.
  --force                Replace existing targets without prompting.
  --skip-neovim-install  Only install/link configs; do not install or update Neovim.
  --skip-zsh-install     Only install/link configs; do not install or update Zsh tooling.
  --skip-agent-toolbox-install
                         Do not install or update the Agent Toolbox Codex plugin.
  -h, --help             Show this help.

Only Neovim, Zsh, Starship, ShellCheck, and Agent Toolbox are installed.
EOF
}

dry_run=0
copy_mode=0
force=0
skip_neovim_install=0
skip_zsh_install=0
skip_agent_toolbox_install=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		--dry-run)
			dry_run=1
			;;
		--copy)
			copy_mode=1
			;;
		--force)
			force=1
			;;
		--skip-neovim-install)
			skip_neovim_install=1
			;;
		--skip-zsh-install)
			skip_zsh_install=1
			;;
		--skip-agent-toolbox-install)
			skip_agent_toolbox_install=1
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 2
			;;
	esac
	shift
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
target_config="${XDG_CONFIG_HOME:-${HOME}/.config}"
backup_root="${target_config}/dotfiles-backups"
timestamp="$(date +%Y%m%d%H%M%S)"

source_nvim="${script_dir}/nvim"
source_zshenv="${script_dir}/zsh/zshenv"
source_zprofile="${script_dir}/zsh/zprofile"
source_zshrc="${script_dir}/zsh/zshrc"
source_zsh_plugins="${script_dir}/zsh/plugins.txt"
source_zsh_plugins_late="${script_dir}/zsh/plugins-late.txt"
source_starship="${script_dir}/starship/starship.toml"
agent_toolbox_marketplace="agent-toolbox"
agent_toolbox_source="chenkeyv/agent-toolbox"
agent_toolbox_selector="${agent_toolbox_marketplace}@${agent_toolbox_marketplace}"

target_nvim="${target_config}/nvim"
target_zsh_dir="${target_config}/zsh"
target_zshenv="${HOME}/.zshenv"
target_zprofile="${HOME}/.zprofile"
target_zshrc_home="${HOME}/.zshrc"
target_zshenv_xdg="${target_zsh_dir}/.zshenv"
target_zprofile_xdg="${target_zsh_dir}/.zprofile"
target_zshrc="${target_zsh_dir}/.zshrc"
target_zsh_plugins="${target_zsh_dir}/plugins.txt"
target_zsh_plugins_late="${target_zsh_dir}/plugins-late.txt"
target_starship="${target_config}/starship.toml"

run() {
	printf '+'
	for arg in "$@"; do
		printf ' %q' "$arg"
	done
	printf '\n'

	if [ "$dry_run" -eq 0 ]; then
		"$@"
	fi
}

run_sudo() {
	if [ "${EUID}" -eq 0 ]; then
		run "$@"
	else
		run sudo "$@"
	fi
}

run_in_dir() {
	local dir="$1"
	shift

	printf '+ cd %q &&' "$dir"
	for arg in "$@"; do
		printf ' %q' "$arg"
	done
	printf '\n'

	if [ "$dry_run" -eq 0 ]; then
		(cd "$dir" && "$@")
	fi
}

ensure_source() {
	local source_path="$1"

	if [ ! -e "$source_path" ]; then
		echo "Missing source path: $source_path" >&2
		exit 1
	fi
}

confirm_replace() {
	local target_path="$1"

	if [ "$force" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
		return
	fi

	printf 'Replace existing %s? [y/N] ' "$target_path"
	read -r answer
	case "$answer" in
		y | Y | yes | YES)
			;;
		*)
			echo "Aborted."
			exit 1
			;;
	esac
}

backup_existing() {
	local target_path="$1"
	local backup_name="$2"

	if [ ! -e "$target_path" ] && [ ! -L "$target_path" ]; then
		return
	fi

	confirm_replace "$target_path"
	run mkdir -p "$backup_root"
	run mv "$target_path" "${backup_root}/${backup_name}.${timestamp}"
}

link_file() {
	local source_path="$1"
	local target_path="$2"
	local backup_name="$3"

	ensure_source "$source_path"
	run mkdir -p "$(dirname "$target_path")"

	if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
		echo "Already linked: $target_path -> $source_path"
		return
	fi

	backup_existing "$target_path" "$backup_name"
	run ln -s "$source_path" "$target_path"
}

install_dir() {
	local source_path="$1"
	local target_path="$2"
	local backup_name="$3"

	ensure_source "$source_path"
	run mkdir -p "$(dirname "$target_path")"

	if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
		echo "Already linked: $target_path -> $source_path"
		return
	fi

	if [ "$copy_mode" -eq 1 ] && [ -d "$target_path" ] && [ ! -L "$target_path" ]; then
		if diff -qr "$source_path" "$target_path" >/dev/null 2>&1; then
			echo "Already copied: $target_path"
			return
		fi
	fi

	backup_existing "$target_path" "$backup_name"

	if [ "$copy_mode" -eq 1 ]; then
		run cp -R "$source_path" "$target_path"
	else
		run ln -s "$source_path" "$target_path"
	fi
}

has_head_neovim() {
	if ! command -v nvim >/dev/null 2>&1; then
		return 1
	fi

	local version
	version="$(nvim --version 2>/dev/null | sed -n '1p')"
	case "$version" in
		*dev* | *HEAD*)
			echo "Neovim HEAD/dev build already installed: $version"
			return 0
			;;
	esac

	return 1
}

detect_brew() {
	if command -v brew >/dev/null 2>&1; then
		return 0
	fi

	local brew_bin
	for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
		if [ -x "$brew_bin" ]; then
			eval "$("$brew_bin" shellenv)"
			return 0
		fi
	done

	return 1
}

ensure_homebrew() {
	if detect_brew; then
		return
	fi

	run bash -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

	if [ "$dry_run" -eq 1 ]; then
		return
	fi

	if ! detect_brew; then
		echo "Homebrew was installed, but brew is still not available in PATH." >&2
		exit 1
	fi
}

is_arch_linux() {
	if [ ! -r /etc/os-release ]; then
		return 1
	fi

	# shellcheck disable=SC1091
	. /etc/os-release
	case " ${ID:-} ${ID_LIKE:-} " in
		*" arch "*)
			return 0
			;;
	esac

	return 1
}

ensure_paru() {
	if command -v paru >/dev/null 2>&1; then
		return
	fi

	if [ "${EUID}" -eq 0 ]; then
		echo "Do not run this script as root on Arch Linux; paru must be built as a normal user." >&2
		exit 1
	fi

	run_sudo pacman -S --needed --noconfirm base-devel git

	local build_dir
	build_dir="${TMPDIR:-/tmp}/paru-build-${timestamp}"
	run mkdir -p "$build_dir"
	run git clone https://aur.archlinux.org/paru.git "${build_dir}/paru"
	run_in_dir "${build_dir}/paru" makepkg -si --noconfirm
}

install_neovim_homebrew() {
	ensure_homebrew

	if command -v brew >/dev/null 2>&1 && HOMEBREW_NO_AUTO_UPDATE=1 brew list --versions neovim >/dev/null 2>&1 && has_head_neovim; then
		return
	elif command -v brew >/dev/null 2>&1 && HOMEBREW_NO_AUTO_UPDATE=1 brew list --versions neovim >/dev/null 2>&1; then
		run env HOMEBREW_NO_AUTO_UPDATE=1 brew reinstall --HEAD neovim
	else
		run env HOMEBREW_NO_AUTO_UPDATE=1 brew install --HEAD neovim
	fi
}

install_neovim_arch() {
	if pacman -Q neovim-git >/dev/null 2>&1; then
		echo "neovim-git is already installed."
		return
	fi

	ensure_paru
	run paru -S --needed --noconfirm neovim-git
}

install_zsh_tools_homebrew() {
	ensure_homebrew
	run env HOMEBREW_NO_AUTO_UPDATE=1 brew install zsh antidote starship fzf zoxide atuin bat lsd fd ripgrep shellcheck
}

install_zsh_tools_arch() {
	ensure_paru
	run paru -S --needed --noconfirm zsh zsh-antidote starship fzf zoxide atuin bat lsd fd ripgrep shellcheck
}

install_neovim() {
	case "$(uname -s)" in
		Darwin)
			install_neovim_homebrew
			;;
		Linux)
			if is_arch_linux; then
				install_neovim_arch
			else
				install_neovim_homebrew
			fi
			;;
		*)
			echo "Unsupported OS: $(uname -s). Install Neovim nightly manually, then rerun this script." >&2
			exit 1
			;;
	esac
}

install_zsh_tools() {
	case "$(uname -s)" in
		Darwin)
			install_zsh_tools_homebrew
			;;
		Linux)
			if is_arch_linux; then
				install_zsh_tools_arch
			else
				install_zsh_tools_homebrew
			fi
			;;
		*)
			echo "Unsupported OS: $(uname -s). Install Zsh tooling manually, then rerun this script." >&2
			exit 1
			;;
	esac
}

has_agent_toolbox_marketplace() {
	codex plugin marketplace list 2>/dev/null |
		awk -v name="$agent_toolbox_marketplace" \
			'$1 == name { found = 1 } END { exit found ? 0 : 1 }'
}

has_agent_toolbox_plugin() {
	codex plugin list 2>/dev/null |
		awk -v selector="$agent_toolbox_selector" \
			'$1 == selector && $2 == "installed," && $3 == "enabled" { found = 1 }
			END { exit found ? 0 : 1 }'
}

install_agent_toolbox() {
	if ! command -v codex >/dev/null 2>&1; then
		if [ "$dry_run" -eq 1 ]; then
			echo "Codex CLI not found; Agent Toolbox installation would require codex."
			run codex plugin marketplace add "$agent_toolbox_source" --ref main
			run codex plugin add "$agent_toolbox_selector"
			return
		fi

		echo "Codex CLI is required to install Agent Toolbox." >&2
		echo "Install Codex or rerun with --skip-agent-toolbox-install." >&2
		exit 1
	fi

	if has_agent_toolbox_marketplace; then
		echo "Agent Toolbox marketplace already configured."
	else
		run codex plugin marketplace add "$agent_toolbox_source" --ref main
	fi

	if has_agent_toolbox_plugin; then
		echo "Agent Toolbox plugin already installed and enabled."
	else
		run codex plugin add "$agent_toolbox_selector"
	fi
}

install_configs() {
	install_dir "$source_nvim" "$target_nvim" "nvim"
	link_file "$source_zshenv" "$target_zshenv" "zshenv"
	link_file "$source_zprofile" "$target_zprofile" "zprofile"
	link_file "$source_zshrc" "$target_zshrc_home" "zshrc.home"
	link_file "$source_zshenv" "$target_zshenv_xdg" "zshenv.xdg"
	link_file "$source_zprofile" "$target_zprofile_xdg" "zprofile.xdg"
	link_file "$source_zshrc" "$target_zshrc" "zshrc"
	link_file "$source_zsh_plugins" "$target_zsh_plugins" "zsh-plugins.txt"
	link_file "$source_zsh_plugins_late" "$target_zsh_plugins_late" "zsh-plugins-late.txt"
	link_file "$source_starship" "$target_starship" "starship.toml"
}

if [ "$skip_neovim_install" -eq 0 ]; then
	install_neovim
fi

if [ "$skip_zsh_install" -eq 0 ]; then
	install_zsh_tools
fi

if [ "$skip_agent_toolbox_install" -eq 0 ]; then
	install_agent_toolbox
fi

install_configs

if [ "$dry_run" -eq 1 ]; then
	echo "Dry run complete. No files were changed."
else
	echo "Dotfiles installed."
fi
