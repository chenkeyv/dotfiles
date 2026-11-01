#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/nvim-smoke.sh [--home <dir>]

Check that the Neovim config really loads. Plain `nvim --headless` exits 0 even
when init.lua raises, so tests/nvim_smoke.lua asserts on the loaded state.

Without options, this tests the repo config using a temporary copy and the nvim
on PATH, cloning plugins at their locked revisions. Set
DOTFILES_SMOKE_DATA_HOME to reuse an existing data directory.

With --home, this tests a home directory prepared by `dotfiles-env apply`, using
its bundled nvim with Git network access blocked.
EOF
}

repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
smoke_test="${repo_root}/tests/nvim_smoke.lua"
bundle_home=""

case "${1:-}" in
	"") ;;
	--home)
		if [ "$#" -lt 2 ] || [ -z "$2" ]; then
			echo "--home requires a directory." >&2
			exit 2
		fi
		bundle_home="$(CDPATH='' cd -- "$2" && pwd)"
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 2
		;;
esac

if [ -n "$bundle_home" ]; then
	env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
		HOME="$bundle_home" \
		GIT_ALLOW_PROTOCOL=none \
		NVIM_LOG_FILE=/dev/null \
		DOTFILES_SMOKE_BUNDLE=1 \
		"${bundle_home}/.local/bin/nvim" --headless -c "luafile ${smoke_test}" </dev/null
else
	work="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-nvim-smoke.XXXXXX")"
	trap 'rm -rf "$work"' EXIT
	mkdir -p "${work}/config"
	# A copy, because vim.pack rewrites the lockfile next to the config.
	cp -R "${repo_root}/nvim" "${work}/config/nvim"

	XDG_CONFIG_HOME="${work}/config" \
		XDG_DATA_HOME="${DOTFILES_SMOKE_DATA_HOME:-${work}/data}" \
		XDG_STATE_HOME="${work}/state" \
		XDG_CACHE_HOME="${work}/cache" \
		NVIM_LOG_FILE=/dev/null \
		nvim --headless -c "luafile ${smoke_test}" </dev/null
fi
printf '\n'
