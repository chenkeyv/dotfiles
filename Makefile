.PHONY: validate

validate:
	bash -n setup.sh
	shellcheck setup.sh
	zsh -n zsh/zshenv zsh/zprofile zsh/zshrc
