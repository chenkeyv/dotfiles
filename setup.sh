#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: ./setup.sh [--dry-run] [--copy] [--force]
                  [--skip-neovim-install] [--skip-zsh-install]
                  [--skip-python-install] [--skip-node-install]
                  [--skip-skillhub-install] [--skip-font-install]
                  [--packages-file <path>]
                  [--skill <skill>]
                  [--skip-skill-install]
                  [--plugin <plugin>]
                  [--skip-plugin-install]
                  [--install-agent-toolbox]

Installs the currently maintained dotfiles.

By default this first links the configs below, then installs Neovim HEAD/nightly,
Zsh tooling, uv with a user-level Python, Node.js with pnpm, the SkillHub CLI,
and the configured Maple Mono NF font:
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
  ~/.config/ghostty/config -> <repo>/ghostty/config

Ghostty must be installed separately.

When Surge's bundled agent skill is selected in codex-packages.json and is
available on macOS, this also links:
  ~/.codex/skills/surge -> /Applications/Surge.app/Contents/Resources/Skills/surge

On Arch Linux, this bootstraps paru when needed and installs neovim-git.
On macOS and other Linux distributions, this installs Homebrew when needed and
uses it to install Neovim HEAD.

Options:
  --dry-run              Print the actions without changing files.
  --copy                 Copy nvim instead of creating a symlink.
  --force                Replace existing targets without prompting.
  --skip-neovim-install  Only install/link configs; do not install or update Neovim.
  --skip-zsh-install     Only install/link configs; do not install or update Zsh tooling.
  --skip-python-install  Do not install uv or the uv-managed user-level Python.
  --skip-node-install    Do not install Node.js or pnpm.
  --skip-skillhub-install
                         Do not install the SkillHub CLI.
  --skip-font-install    Do not install the Maple Mono NF font used by Ghostty.
  --packages-file <path> Read plugins and skills from this JSON file instead of
                         <repo>/codex-packages.json.
  --skill <skill>        Install a configured skill into Codex. Repeat as needed.
  --skip-skill-install   Do not install skills from the file or --skill options.
  --plugin <plugin>      Install a PLUGIN@MARKETPLACE selector. Repeat as needed.
  --skip-plugin-install  Do not install plugins from the file or --plugin options.
  --install-agent-toolbox
                         Also request Agent Toolbox (kept for compatibility).
  -h, --help             Show this help.

Only Neovim, Zsh, Starship, ShellCheck, uv, user-level Python, Node.js, pnpm,
the SkillHub CLI, Maple Mono NF, configured skills, configured Codex plugins,
and the bundled Surge skill when selected are installed by default.
EOF
}

dry_run=0
copy_mode=0
force=0
skip_neovim_install=0
skip_zsh_install=0
skip_python_install=0
skip_node_install=0
skip_skillhub_install=0
skip_font_install=0
skip_skill_install=0
skip_plugin_install=0
install_agent_toolbox_requested=0
packages_file=""
requested_skills=()
requested_plugins=()

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
		--skip-python-install)
			skip_python_install=1
			;;
		--skip-node-install)
			skip_node_install=1
			;;
		--skip-skillhub-install)
			skip_skillhub_install=1
			;;
		--skip-font-install)
			skip_font_install=1
			;;
		--packages-file)
			if [ "$#" -lt 2 ] || [ -z "$2" ]; then
				echo "--packages-file requires a path." >&2
				exit 2
			fi
			packages_file="$2"
			shift
			;;
		--skill)
			if [ "$#" -lt 2 ] || [ -z "$2" ]; then
				echo "--skill requires a skill name." >&2
				exit 2
			fi
			requested_skills+=("$2")
			shift
			;;
		--skip-skill-install)
			skip_skill_install=1
			;;
		--plugin)
			if [ "$#" -lt 2 ] || [ -z "$2" ]; then
				echo "--plugin requires a PLUGIN@MARKETPLACE selector." >&2
				exit 2
			fi
			requested_plugins+=("$2")
			shift
			;;
		--skip-plugin-install)
			skip_plugin_install=1
			;;
		--install-agent-toolbox)
			install_agent_toolbox_requested=1
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
packages_file="${packages_file:-${script_dir}/codex-packages.json}"
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
source_ghostty="${script_dir}/ghostty/config"
source_surge_skill="${DOTFILES_SURGE_SKILL_SOURCE:-/Applications/Surge.app/Contents/Resources/Skills/surge}"
source_personal_marketplace_helper="${script_dir}/scripts/ensure-personal-codex-marketplace.py"
agent_toolbox_name="agent-toolbox"
agent_toolbox_marketplace="personal"
agent_toolbox_source_url="https://github.com/chenkeyv/agent-toolbox.git"
agent_toolbox_selector="${agent_toolbox_name}@${agent_toolbox_marketplace}"
skillhub_installer_url="https://skillhub-1388575217.cos.ap-guangzhou.myqcloud.com/install/install.sh"
user_python_version="3.14"
zsh_tools_homebrew=(zsh antidote starship fzf zoxide atuin bat lsd fd ripgrep shellcheck)
zsh_tools_arch=(zsh zsh-antidote starship fzf zoxide atuin bat lsd fd ripgrep shellcheck)
node_tools_homebrew=(node pnpm)
node_tools_arch=(nodejs pnpm)
# Keep these packages aligned with font-family in ghostty/config.
ghostty_font_homebrew="font-maple-mono-nf"
ghostty_font_arch="maplemono-nf-unhinted"

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
target_ghostty="${target_config}/ghostty/config"
target_surge_skill="${CODEX_HOME:-${HOME}/.codex}/skills/surge"
target_agent_skills="${HOME}/.agents/skills"
target_legacy_codex_skills="${CODEX_HOME:-${HOME}/.codex}/skills"
target_personal_marketplace="${HOME}/.agents/plugins/marketplace.json"
skillhub_cli_target="${HOME}/.local/bin/skillhub"
agent_toolbox_marketplace_changed=0

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
	version="$(NVIM_LOG_FILE=/dev/null nvim --version 2>/dev/null | sed -n '1p')"
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

	local install_url
	install_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
	run env NONINTERACTIVE=1 bash -c \
		"/bin/bash -c \"\$(curl -fsSL \"\$1\")\"" \
		bash \
		"$install_url"

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

	if command -v brew >/dev/null 2>&1 &&
		HOMEBREW_NO_AUTO_UPDATE=1 brew list --versions neovim >/dev/null 2>&1 &&
		has_head_neovim
	then
		return
	elif command -v brew >/dev/null 2>&1 &&
		HOMEBREW_NO_AUTO_UPDATE=1 brew list --versions neovim >/dev/null 2>&1
	then
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
	run env HOMEBREW_NO_AUTO_UPDATE=1 brew install "${zsh_tools_homebrew[@]}"
}

install_zsh_tools_arch() {
	ensure_paru
	run paru -S --needed --noconfirm "${zsh_tools_arch[@]}"
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

install_font_homebrew() {
	ensure_homebrew

	if command -v brew >/dev/null 2>&1 &&
		HOMEBREW_NO_AUTO_UPDATE=1 brew list --cask --versions "$ghostty_font_homebrew" >/dev/null 2>&1
	then
		echo "Maple Mono NF is already installed."
		return
	fi

	run env HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask "$ghostty_font_homebrew"
}

install_font_arch() {
	if pacman -Q "$ghostty_font_arch" >/dev/null 2>&1; then
		echo "Maple Mono NF is already installed."
		return
	fi

	ensure_paru
	run paru -S --needed --noconfirm "$ghostty_font_arch"
}

install_font() {
	case "$(uname -s)" in
		Darwin)
			install_font_homebrew
			;;
		Linux)
			if is_arch_linux; then
				install_font_arch
			else
				install_font_homebrew
			fi
			;;
		*)
			echo "Unsupported OS: $(uname -s). Install Maple Mono NF manually, then rerun with --skip-font-install." >&2
			exit 1
			;;
	esac
}

install_uv() {
	case "$(uname -s)" in
		Darwin)
			ensure_homebrew
			run env HOMEBREW_NO_AUTO_UPDATE=1 brew install uv
			;;
		Linux)
			if is_arch_linux; then
				ensure_paru
				run paru -S --needed --noconfirm uv
			else
				ensure_homebrew
				run env HOMEBREW_NO_AUTO_UPDATE=1 brew install uv
			fi
			;;
		*)
			echo "Unsupported OS: $(uname -s). Install uv manually, then rerun this script." >&2
			exit 1
			;;
	esac
}

has_user_python() {
	local managed_python python_bin_dir executable

	managed_python="$(
		uv python find --managed-python --no-python-downloads --no-project \
			"$user_python_version" 2>/dev/null
	)" || return 1
	python_bin_dir="$(uv python dir --bin 2>/dev/null)" || return 1

	for executable in python python3 "python${user_python_version}"; do
		if [ ! -L "${python_bin_dir}/${executable}" ] ||
			[ "$(readlink "${python_bin_dir}/${executable}")" != "$managed_python" ]
		then
			return 1
		fi
	done

	echo "uv-managed Python ${user_python_version} already installed as the user default."
}

activate_user_python() {
	local python_bin_dir

	python_bin_dir="$(uv python dir --bin 2>/dev/null)" || return 1
	case ":${PATH}:" in
		*":${python_bin_dir}:"*)
			;;
		*)
			PATH="${python_bin_dir}:${PATH}"
			export PATH
			;;
	esac
	hash -r
}

find_python3() {
	local managed_python

	if command -v python3 >/dev/null 2>&1; then
		command -v python3
		return
	fi

	if command -v uv >/dev/null 2>&1; then
		managed_python="$(
			uv python find --managed-python --no-python-downloads --no-project \
				"$user_python_version" 2>/dev/null
		)" || true
		if [ -n "$managed_python" ] && [ -x "$managed_python" ]; then
			printf '%s\n' "$managed_python"
			return
		fi
	fi

	if [ -x "${HOME}/.local/bin/python3" ]; then
		printf '%s\n' "${HOME}/.local/bin/python3"
		return
	fi

	return 1
}

install_user_python() {
	install_uv

	if [ "$dry_run" -eq 0 ]; then
		hash -r
		if ! command -v uv >/dev/null 2>&1; then
			echo "uv was installed, but it is still not available in PATH." >&2
			exit 1
		fi

		if has_user_python; then
			activate_user_python
			return
		fi
	fi

	run uv python install "$user_python_version" --default
	if [ "$dry_run" -eq 0 ]; then
		activate_user_python
	fi
}

install_node_tools_homebrew() {
	ensure_homebrew
	run env HOMEBREW_NO_AUTO_UPDATE=1 brew install "${node_tools_homebrew[@]}"
}

install_node_tools_arch() {
	ensure_paru
	run paru -S --needed --noconfirm "${node_tools_arch[@]}"
}

install_node_tools() {
	case "$(uname -s)" in
		Darwin)
			install_node_tools_homebrew
			;;
		Linux)
			if is_arch_linux; then
				install_node_tools_arch
			else
				install_node_tools_homebrew
			fi
			;;
		*)
			echo "Unsupported OS: $(uname -s). Install Node.js and pnpm manually, then rerun this script." >&2
			exit 1
			;;
	esac
}

find_skillhub_cli() {
	if command -v skillhub >/dev/null 2>&1; then
		command -v skillhub
	elif [ -x "$skillhub_cli_target" ]; then
		printf '%s\n' "$skillhub_cli_target"
	else
		return 1
	fi
}

has_skillhub_cli() {
	local executable version

	executable="$(find_skillhub_cli)" || return 1
	version="$("$executable" --version 2>/dev/null)" || return 1
	echo "SkillHub CLI already installed: $version"
}

install_skillhub_cli() {
	if has_skillhub_cli; then
		return
	fi

	run bash -o pipefail -c \
		"curl -fsSL \"\$1\" | bash -s -- --cli-only" \
		bash \
		"$skillhub_installer_url"

	if [ "$dry_run" -eq 0 ]; then
		hash -r
		if ! has_skillhub_cli; then
			echo "SkillHub installer completed, but a working CLI was not found." >&2
			exit 1
		fi
	fi
}

skillhub_ref_name() {
	local skill_ref="$1"

	case "$skill_ref" in
		@*/*@*)
			printf '%s\n' "${skill_ref%@*}"
			;;
		@*/*)
			printf '%s\n' "$skill_ref"
			;;
		*@*)
			printf '%s\n' "${skill_ref%%@*}"
			;;
		*)
			printf '%s\n' "$skill_ref"
			;;
	esac
}

configured_skill_name() {
	local skill="$1"

	case "$skill" in
		skillhub:*)
			skillhub_ref_name "${skill#skillhub:}"
			;;
		app:* | local:*)
			printf '%s\n' "${skill#*:}"
			;;
		*)
			skillhub_ref_name "$skill"
			;;
	esac
}

is_configured_skill_installed() {
	local skill_name="$1"
	local executable

	if [ -f "${target_agent_skills}/${skill_name}/SKILL.md" ] ||
		[ -f "${target_legacy_codex_skills}/${skill_name}/SKILL.md" ]
	then
		return 0
	fi

	executable="$(find_skillhub_cli)" || return 1
	"$executable" --skip-self-upgrade list --dir "$target_agent_skills" 2>/dev/null |
		awk -v skill="$skill_name" '$1 == skill { found = 1 } END { exit found ? 0 : 1 }'
}

validate_skill_entry() {
	local skill="$1"

	case "$skill" in
		-* | *[[:space:]]*)
			echo "Invalid skill entry: $skill" >&2
			exit 2
			;;
	esac
}

append_skill() {
	local skill="$1"
	local existing

	if [ -z "$skill" ]; then
		return
	fi
	validate_skill_entry "$skill"

	if [ "${#requested_skills[@]}" -gt 0 ]; then
		for existing in "${requested_skills[@]}"; do
			if [ "$existing" = "$skill" ]; then
				return
			fi
		done
	fi
	requested_skills+=("$skill")
}

read_package_entries() {
	local key="$1"
	local python_executable

	if [ ! -f "$packages_file" ]; then
		echo "Codex packages file not found: $packages_file" >&2
		return 1
	fi
	python_executable="$(find_python3)" || true
	if [ -z "$python_executable" ]; then
		echo "Python 3 is required to read $packages_file." >&2
		return 1
	fi

	"$python_executable" - "$packages_file" "$key" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"Invalid Codex packages JSON: {exc}")

if not isinstance(data, dict) or data.get("version") != 1:
    raise SystemExit("Codex packages JSON must be an object with version 1")
for required in ("plugins", "skills"):
    if not isinstance(data.get(required), list):
        raise SystemExit(f"Codex packages JSON field {required!r} must be an array")

def token(value, field):
    if not isinstance(value, str) or not value or any(char.isspace() for char in value):
        raise SystemExit(f"Codex packages entry field {field!r} must be a non-empty token")
    return value

if key == "plugins":
    for entry in data[key]:
        print(token(entry, "plugins[]"))
elif key == "skills":
    for entry in data[key]:
        if isinstance(entry, str):
            print(token(entry, "skills[]"))
            continue
        if not isinstance(entry, dict):
            raise SystemExit("Each skill entry must be a string or object")
        installer = token(entry.get("installer"), "installer")
        name = token(entry.get("name"), "name")
        if installer == "skillhub":
            reference = token(entry.get("reference", name), "reference")
            print(f"skillhub:{reference}")
        elif installer == "app":
            if name != "surge":
                raise SystemExit(f"Unsupported app skill: {name}")
            print(f"app:{name}")
        elif installer == "local":
            print(f"{installer}:{name}")
        else:
            raise SystemExit(f"Unsupported skill installer: {installer}")
else:
    raise SystemExit(f"Unknown Codex packages field: {key}")
PY
}

load_configured_skills() {
	local entries line

	entries="$(read_package_entries skills)" || exit 1
	while IFS= read -r line || [ -n "$line" ]; do
		append_skill "$line"
	done <<<"$entries"

	if [ "${#requested_skills[@]}" -gt 0 ]; then
		for line in "${requested_skills[@]}"; do
			validate_skill_entry "$line"
		done
	fi
}

install_skillhub_ref() {
	local skill_ref="$1"
	local executable

	executable="$(find_skillhub_cli)" || true
	if [ -z "$executable" ]; then
		if [ "$dry_run" -eq 1 ] && [ "$skip_skillhub_install" -eq 0 ]; then
			executable="$skillhub_cli_target"
		else
			echo "SkillHub CLI is required to install configured skills." >&2
			echo "Rerun without --skip-skillhub-install or skip skills with --skip-skill-install." >&2
			exit 1
		fi
	fi
	run "$executable" --skip-self-upgrade install "$skill_ref" --dir "$target_agent_skills"
}

install_configured_skills() {
	local skill skill_name

	load_configured_skills
	if [ "${#requested_skills[@]}" -eq 0 ]; then
		return
	fi

	for skill in "${requested_skills[@]}"; do
		skill_name="$(configured_skill_name "$skill")"
		case "$skill" in
			app:surge)
				install_surge_skill
				;;
			local:*)
				if is_configured_skill_installed "$skill_name"; then
					echo "Codex skill already installed: $skill_name"
				else
					echo "Local-only Codex skill is not available on this machine: $skill_name" >&2
				fi
				;;
			skillhub:*)
				if is_configured_skill_installed "$skill_name"; then
					echo "Codex skill already installed: $skill_name"
				else
					install_skillhub_ref "${skill#skillhub:}"
				fi
				;;
			*)
				if is_configured_skill_installed "$skill_name"; then
					echo "Codex skill already installed: $skill_name"
				else
					install_skillhub_ref "$skill"
				fi
				;;
		esac
	done
}

validate_plugin_selector() {
	local plugin="$1"

	case "$plugin" in
		-* | *[[:space:]]*)
			echo "Invalid Codex plugin selector: $plugin" >&2
			exit 2
			;;
	esac
	case "$plugin" in
		*@*)
			;;
		*)
			echo "Invalid Codex plugin selector: $plugin" >&2
			exit 2
			;;
	esac
}

append_plugin() {
	local plugin="$1"
	local existing

	if [ -z "$plugin" ]; then
		return
	fi
	validate_plugin_selector "$plugin"

	if [ "${#requested_plugins[@]}" -gt 0 ]; then
		for existing in "${requested_plugins[@]}"; do
			if [ "$existing" = "$plugin" ]; then
				return
			fi
		done
	fi
	requested_plugins+=("$plugin")
}

load_configured_plugins() {
	local entries line

	entries="$(read_package_entries plugins)" || exit 1
	while IFS= read -r line || [ -n "$line" ]; do
		append_plugin "$line"
	done <<<"$entries"

	if [ "$install_agent_toolbox_requested" -eq 1 ]; then
		append_plugin "$agent_toolbox_selector"
	fi

	if [ "${#requested_plugins[@]}" -gt 0 ]; then
		for line in "${requested_plugins[@]}"; do
			validate_plugin_selector "$line"
		done
	fi
}

has_codex_plugin() {
	local plugin_selector="$1"
	local payload python_executable

	payload="$(codex plugin list --json 2>/dev/null)" || return 1
	python_executable="$(find_python3)" || return 1
	"$python_executable" - "$plugin_selector" "$payload" <<'PY'
import json
import sys

selector = sys.argv[1]
try:
    data = json.loads(sys.argv[2])
except json.JSONDecodeError:
    raise SystemExit(1)

installed = data.get("installed", []) if isinstance(data, dict) else []
for plugin in installed:
    if not isinstance(plugin, dict):
        continue
    if (
        plugin.get("pluginId") == selector
        and plugin.get("installed") is True
        and plugin.get("enabled") is True
    ):
        raise SystemExit(0)

raise SystemExit(1)
PY
}

ensure_agent_toolbox_marketplace() {
	local python_executable status

	ensure_source "$source_personal_marketplace_helper"
	python_executable="$(find_python3)" || {
		echo "Python 3 is required to configure the personal Codex marketplace." >&2
		exit 1
	}

	if "$python_executable" "$source_personal_marketplace_helper" --check \
		"$target_personal_marketplace" "$agent_toolbox_source_url"
	then
		echo "Agent Toolbox personal marketplace already configured."
		agent_toolbox_marketplace_changed=0
		return
	else
		status=$?
		if [ "$status" -ne 1 ]; then
			exit "$status"
		fi
	fi

	echo "Configuring Agent Toolbox in the personal Codex marketplace."
	agent_toolbox_marketplace_changed=1
	run "$python_executable" "$source_personal_marketplace_helper" \
		"$target_personal_marketplace" "$agent_toolbox_source_url"
}

install_configured_plugins() {
	local plugin

	load_configured_plugins
	if [ "${#requested_plugins[@]}" -eq 0 ]; then
		return
	fi

	if ! command -v codex >/dev/null 2>&1; then
		if [ "$dry_run" -eq 1 ]; then
			echo "Codex CLI not found; configured plugin installation would require codex."
		else
			echo "Codex CLI is required to install configured plugins." >&2
			exit 1
		fi
	fi

	for plugin in "${requested_plugins[@]}"; do
		agent_toolbox_marketplace_changed=0
		if [ "$plugin" = "$agent_toolbox_selector" ]; then
			ensure_agent_toolbox_marketplace
		fi

		if command -v codex >/dev/null 2>&1 &&
			has_codex_plugin "$plugin" &&
			[ "$agent_toolbox_marketplace_changed" -eq 0 ]
		then
			echo "Codex plugin already installed and enabled: $plugin"
			continue
		fi

		run codex plugin add "$plugin"
	done
}

install_surge_skill() {
	if [ ! -d "$source_surge_skill" ]; then
		echo "Surge agent skill not available; skipping."
		return
	fi

	link_file "$source_surge_skill" "$target_surge_skill" "codex-skill-surge"
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
	link_file "$source_ghostty" "$target_ghostty" "ghostty-config"
}

# Keep startup files in place even if a later tool or plugin install fails.
install_configs

if [ "$dry_run" -eq 0 ]; then
	echo "Dotfile configs installed. Once Zsh is available, load them with: exec zsh -l"
fi

if [ "$skip_neovim_install" -eq 0 ]; then
	install_neovim
fi

if [ "$skip_zsh_install" -eq 0 ]; then
	install_zsh_tools
fi

if [ "$skip_python_install" -eq 0 ]; then
	install_user_python
fi

if [ "$skip_node_install" -eq 0 ]; then
	install_node_tools
fi

if [ "$skip_skillhub_install" -eq 0 ]; then
	install_skillhub_cli
fi

if [ "$skip_font_install" -eq 0 ]; then
	install_font
fi

if [ "$skip_skill_install" -eq 0 ]; then
	install_configured_skills
fi

if [ "$skip_plugin_install" -eq 0 ]; then
	install_configured_plugins
fi

if [ "$dry_run" -eq 1 ]; then
	echo "Dry run complete. No files were changed."
else
	echo "Dotfiles installed."
	echo "Load the Zsh configuration in this terminal with: exec zsh -l"
fi
