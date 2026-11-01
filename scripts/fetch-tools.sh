#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/fetch-tools.sh [TARGET] [DEST] [DATA_DEST]

Download portable user-space tools for offline dotfiles bundles, and prepare the
data the configs need to work without a network.

Targets: linux-amd64, darwin-arm64, darwin-amd64.
The default target is linux-amd64, intended for Ubuntu 22.04 or later without
sudo; Neovim nightly itself needs glibc 2.34. Tools are copied into DEST/bin, with support files under DEST/opt. Neovim
plugins, Tree-sitter parsers, antidote, and Zsh plugins are prepared in
DATA_DEST. Parsers are compiled, so the host must match TARGET.
EOF
}

target="${1:-linux-amd64}"
dest="${2:-dist/tools/${target}}"
data_dest="${3:-dist/data/${target}}"
repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

case "$target" in
	linux-amd64)
		rust_target="x86_64-unknown-linux-musl"
		fzf_target="linux_amd64"
		shellcheck_target="linux.x86_64"
		neovim_pattern="nvim-linux-x86_64.tar.gz"
		tree_sitter_target="linux-x64"
		;;
	darwin-arm64)
		rust_target="aarch64-apple-darwin"
		fzf_target="darwin_arm64"
		shellcheck_target="darwin.aarch64"
		neovim_pattern="nvim-macos-arm64.tar.gz"
		tree_sitter_target="macos-arm64"
		;;
	darwin-amd64)
		rust_target="x86_64-apple-darwin"
		fzf_target="darwin_amd64"
		shellcheck_target="darwin.x86_64"
		neovim_pattern="nvim-macos-x86_64.tar.gz"
		tree_sitter_target="macos-x64"
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "unsupported target: $target" >&2
		exit 2
		;;
esac

require() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "required command not found: $1" >&2
		exit 1
	fi
}

require gh
require tar
require git
require gunzip
require zsh

mkdir -p "${dest}/bin" "$data_dest"
data_dest="$(CDPATH='' cd -- "$data_dest" && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tools.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

host_matches_target() {
	local os
	local arch

	os="$(uname -s)"
	arch="$(uname -m)"
	case "$target" in
		linux-amd64)
			[ "$os" = Linux ] && [ "$arch" = x86_64 ]
			;;
		darwin-arm64)
			[ "$os" = Darwin ] && [ "$arch" = arm64 ]
			;;
		darwin-amd64)
			[ "$os" = Darwin ] && [ "$arch" = x86_64 ]
			;;
		*)
			return 1
			;;
	esac
}

if ! host_matches_target; then
	echo "bundle data for $target must be built on a native $target host" >&2
	exit 1
fi

download_tool() {
	local name="$1"
	local repo="$2"
	local pattern="$3"
	local binary="$4"
	local output_name="$5"
	local release="${6:-latest}"
	local required="${7:-required}"
	local work="${tmp_dir}/${name}"
	local gh_args

	mkdir -p "$work"
	if [ "$release" = latest ]; then
		gh_args=(release download --repo "$repo" --pattern "$pattern" --dir "$work" --clobber)
	else
		gh_args=(release download "$release" --repo "$repo" --pattern "$pattern" --dir "$work" --clobber)
	fi
	if ! gh "${gh_args[@]}"; then
		if [ "$required" = required ]; then
			echo "failed to download required tool: $name" >&2
			exit 1
		fi
		echo "skipped optional tool: $name" >&2
		return 0
	fi

	local asset
	asset="$(find "$work" -type f -print -quit)"
	case "$asset" in
		*.tar.gz | *.tgz)
			tar -xzf "$asset" -C "$work"
			;;
		*.tar.xz)
			tar -xJf "$asset" -C "$work"
			;;
		*)
			echo "unsupported archive for $name: $asset" >&2
			exit 1
			;;
	esac

	local extracted
	extracted="$(find "$work" -type f -name "$binary" -perm -111 -print -quit)"
	if [ -z "$extracted" ]; then
		extracted="$(find "$work" -type f -name "$binary" -print -quit)"
	fi
	if [ -z "$extracted" ]; then
		if [ "$required" = required ]; then
			echo "could not find $binary in $name archive" >&2
			exit 1
		fi
		echo "skipped optional tool without binary: $name" >&2
		return 0
	fi

	cp "$extracted" "${dest}/bin/${output_name}"
	chmod 755 "${dest}/bin/${output_name}"
}

build_fd_from_source() {
	local install_root="${tmp_dir}/fd-install"
	local cargo_home="${tmp_dir}/cargo-home"

	require cargo
	CARGO_HOME="$cargo_home" cargo install fd-find --locked --root "$install_root"
	cp "${install_root}/bin/fd" "${dest}/bin/fd"
	chmod 755 "${dest}/bin/fd"
}

download_neovim_nightly() {
	local work="${tmp_dir}/neovim"
	local asset
	local extracted
	local root
	local opt_dir="${dest}/opt/neovim"

	mkdir -p "$work"
	if ! gh release download nightly --repo neovim/neovim --pattern "$neovim_pattern" --dir "$work" --clobber; then
		echo "failed to download required tool: neovim nightly" >&2
		exit 1
	fi

	asset="$(find "$work" -type f -name "$neovim_pattern" -print -quit)"
	if [ -z "$asset" ]; then
		echo "could not find neovim nightly archive matching $neovim_pattern" >&2
		exit 1
	fi
	tar -xzf "$asset" -C "$work"

	extracted="$(find "$work" -type f -path '*/bin/nvim' -perm -111 -print -quit)"
	if [ -z "$extracted" ]; then
		echo "could not find nvim in neovim nightly archive" >&2
		exit 1
	fi
	root="$(CDPATH='' cd -- "$(dirname -- "$extracted")/.." && pwd)"

	rm -rf "$opt_dir"
	mkdir -p "${dest}/opt"
	cp -R "$root" "$opt_dir"
	cat >"${dest}/bin/nvim" <<'EOF'
#!/bin/sh
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec "$script_dir/../opt/neovim/bin/nvim" "$@"
EOF
	chmod 755 "${dest}/bin/nvim"
}

# Puts tree-sitter in the returned directory for compiling parsers. It is a build
# tool only, so the bundle does not ship it.
prepare_tree_sitter_cli() {
	local bin_dir="${tmp_dir}/tree-sitter-bin"
	local asset="tree-sitter-${tree_sitter_target}"

	mkdir -p "$bin_dir"
	if ! gh release download --repo tree-sitter/tree-sitter --pattern "${asset}.gz" --dir "$bin_dir" --clobber; then
		echo "failed to download required tool: tree-sitter CLI" >&2
		exit 1
	fi
	gunzip -f "${bin_dir}/${asset}.gz"
	mv "${bin_dir}/${asset}" "${bin_dir}/tree-sitter"
	chmod 755 "${bin_dir}/tree-sitter"
	"${bin_dir}/tree-sitter" --version
}

build_zsh_data() {
	local antidote_dir="${data_dest}/dotfiles/antidote"
	local antidote_home="${data_dest}/dotfiles/antidote-home"

	rm -rf "$antidote_dir" "$antidote_home"
	mkdir -p "${data_dest}/dotfiles"
	git clone --quiet --depth 1 https://github.com/mattmc3/antidote.git "$antidote_dir"
	rm -rf "${antidote_dir}/.git"

	# Bundling clones each plugin into ANTIDOTE_HOME, where zshrc finds them later.
	# shellcheck disable=SC2016
	ANTIDOTE_HOME="$antidote_home" zsh -f -c '
		source "$1/antidote.zsh"
		antidote bundle <"$2/zsh/plugins.txt" >/dev/null || exit 1
		antidote bundle <"$2/zsh/plugins-late.txt" >/dev/null || exit 1
	' zsh "$antidote_dir" "$repo_root"
}

build_neovim_data() {
	local work="${tmp_dir}/nvim-build"

	prepare_tree_sitter_cli
	mkdir -p "${work}/config" "${work}/state" "${work}/cache"
	cp -R "${repo_root}/nvim" "${work}/config/nvim"
	rm -f "${work}/config/nvim/nvim.log"

	# Runs the real config, so plugins land at the revisions in the lockfile.
	XDG_CONFIG_HOME="${work}/config" \
		XDG_DATA_HOME="$data_dest" \
		XDG_STATE_HOME="${work}/state" \
		XDG_CACHE_HOME="${work}/cache" \
		NVIM_LOG_FILE=/dev/null \
		PATH="${tmp_dir}/tree-sitter-bin:${PATH}" \
		"${dest}/bin/nvim" --headless -c "luafile ${repo_root}/scripts/prepare-nvim-data.lua" </dev/null
	printf '\n'
}

download_tool ripgrep BurntSushi/ripgrep "ripgrep-*-${rust_target}.tar.gz" rg rg
download_tool fd sharkdp/fd "fd-*-${rust_target}.tar.gz" fd fd latest optional
if [ ! -x "${dest}/bin/fd" ]; then
	build_fd_from_source
fi
download_tool bat sharkdp/bat "bat-*-${rust_target}.tar.gz" bat bat
download_tool starship starship/starship "starship-${rust_target}.tar.gz" starship starship
download_tool zoxide ajeetdsouza/zoxide "zoxide-*-${rust_target}.tar.gz" zoxide zoxide
download_tool fzf junegunn/fzf "fzf-*-${fzf_target}.tar.gz" fzf fzf
download_tool shellcheck koalaman/shellcheck "shellcheck-*.${shellcheck_target}.tar.gz" shellcheck shellcheck
download_tool atuin atuinsh/atuin "atuin-${rust_target}.tar.gz" atuin atuin latest optional
download_neovim_nightly
build_zsh_data
build_neovim_data

printf 'Downloaded tools into %s:\n' "$dest"
find "$dest" -maxdepth 4 -type f -perm -111 -print | sort
printf 'Prepared data in %s:\n' "$data_dest"
du -sh "${data_dest}/nvim/site" "${data_dest}/dotfiles"
