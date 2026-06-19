#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: ./setup.sh [--dry-run] [--copy] [--force] [--skip-neovim-install]

Installs the currently maintained dotfiles.

By default this installs Neovim HEAD/nightly and links the Neovim config:
  ~/.config/nvim -> <repo>/nvim

On Arch Linux, this bootstraps paru when needed and installs neovim-git.
On macOS and other Linux distributions, this installs Homebrew when needed and
uses it to install Neovim HEAD.

Options:
  --dry-run              Print the actions without changing files.
  --copy                 Copy nvim instead of creating a symlink.
  --force                Replace an existing ~/.config/nvim without prompting.
  --skip-neovim-install  Only install the config; do not install or update Neovim.
  -h, --help             Show this help.

Other configs in this repo are intentionally not installed because they are stale.
EOF
}

dry_run=0
copy_mode=0
force=0
skip_neovim_install=0

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
source_nvim="${script_dir}/nvim"
target_config="${XDG_CONFIG_HOME:-${HOME}/.config}"
target_nvim="${target_config}/nvim"
backup_root="${target_config}/dotfiles-backups"
timestamp="$(date +%Y%m%d%H%M%S)"

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
	if [ ! -d "$source_nvim" ]; then
		echo "Missing source directory: $source_nvim" >&2
		exit 1
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

install_neovim_arch() {
	if pacman -Q neovim-git >/dev/null 2>&1; then
		echo "neovim-git is already installed."
		return
	fi

	ensure_paru
	run paru -S --needed --noconfirm neovim-git
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

confirm_replace() {
	if [ "$force" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
		return
	fi

	printf 'Replace existing %s? [y/N] ' "$target_nvim"
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
	if [ ! -e "$target_nvim" ] && [ ! -L "$target_nvim" ]; then
		return
	fi

	if [ -L "$target_nvim" ] && [ "$(readlink "$target_nvim")" = "$source_nvim" ]; then
		echo "Neovim config is already linked: $target_nvim -> $source_nvim"
		exit 0
	fi

	confirm_replace
	run mkdir -p "$backup_root"
	run mv "$target_nvim" "${backup_root}/nvim.${timestamp}"
}

install_nvim() {
	ensure_source
	run mkdir -p "$target_config"
	backup_existing

	if [ "$copy_mode" -eq 1 ]; then
		run cp -R "$source_nvim" "$target_nvim"
	else
		run ln -s "$source_nvim" "$target_nvim"
	fi
}

if [ "$skip_neovim_install" -eq 0 ]; then
	install_neovim
fi
install_nvim

if [ "$dry_run" -eq 1 ]; then
	echo "Dry run complete. No files were changed."
else
	echo "Neovim config installed."
fi
