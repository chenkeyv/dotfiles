#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/fetch-tools.sh [TARGET] [DEST]

Download portable user-space tools for offline dotfiles bundles.

Targets: linux-amd64, darwin-arm64, darwin-amd64.
The default target is linux-amd64, intended for Ubuntu 20.04 or later without
sudo. Tools are copied into DEST/bin, with support files under DEST/opt.
EOF
}

target="${1:-linux-amd64}"
dest="${2:-dist/tools/${target}}"

case "$target" in
	linux-amd64)
		rust_target="x86_64-unknown-linux-musl"
		fzf_target="linux_amd64"
		shellcheck_target="linux.x86_64"
		neovim_pattern="nvim-linux-x86_64.tar.gz"
		;;
	darwin-arm64)
		rust_target="aarch64-apple-darwin"
		fzf_target="darwin_arm64"
		shellcheck_target="darwin.aarch64"
		neovim_pattern="nvim-macos-arm64.tar.gz"
		;;
	darwin-amd64)
		rust_target="x86_64-apple-darwin"
		fzf_target="darwin_amd64"
		shellcheck_target="darwin.x86_64"
		neovim_pattern="nvim-macos-x86_64.tar.gz"
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

mkdir -p "${dest}/bin"
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

	if ! host_matches_target; then
		echo "fd prebuilt asset is unavailable for $target, and source build requires a native $target host" >&2
		exit 1
	fi
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

printf 'Downloaded tools into %s:\n' "$dest"
find "$dest" -maxdepth 4 -type f -perm -111 -print | sort
