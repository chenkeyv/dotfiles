.PHONY: validate smoke

validate:
	bash -n setup.sh
	bash -n scripts/fetch-tools.sh
	bash -n scripts/nvim-smoke.sh
	shellcheck setup.sh scripts/fetch-tools.sh scripts/nvim-smoke.sh
	python3 -m json.tool codex-packages.json >/dev/null
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests
	go test ./...
	CGO_ENABLED=0 go build -trimpath -o /tmp/dotfiles ./cmd/dotfiles
	set -e; payload=cmd/dotfiles/payload; trap 'rm -rf "$$payload"' EXIT; /tmp/dotfiles pack -o "$$payload"; CGO_ENABLED=0 go build -tags embedded -trimpath -o /tmp/dotfiles-embedded ./cmd/dotfiles; /tmp/dotfiles-embedded list >/dev/null
	# One file per command: zsh -n treats any further files as script arguments.
	for file in zsh/zshenv zsh/zprofile zsh/zshrc; do zsh -n "$$file" || exit 1; done
	$(MAKE) smoke

smoke:
	scripts/nvim-smoke.sh
