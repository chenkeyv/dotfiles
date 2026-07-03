.PHONY: validate

validate:
	bash -n setup.sh
	bash -n scripts/fetch-tools.sh
	shellcheck setup.sh scripts/fetch-tools.sh
	go test ./...
	CGO_ENABLED=0 go build -trimpath -o /tmp/dotfiles ./cmd/dotfiles
	set -e; payload=cmd/dotfiles/payload; trap 'rm -rf "$$payload"' EXIT; /tmp/dotfiles pack -o "$$payload"; CGO_ENABLED=0 go build -tags embedded -trimpath -o /tmp/dotfiles-embedded ./cmd/dotfiles; /tmp/dotfiles-embedded list >/dev/null
	zsh -n zsh/zshenv zsh/zprofile zsh/zshrc
