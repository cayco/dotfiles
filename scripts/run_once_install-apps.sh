#!/bin/bash

{{ if eq .chezmoi.os "darwin" -}}
# macOS installation
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

brew bundle --file={{ .chezmoi.sourceDir }}/Brewfile --verbose --force

{{ else if eq .chezmoi.os "linux" -}}
# Linux installation
{{ if eq .chezmoi.osRelease.id "ubuntu" -}}
sudo apt update && sudo apt install -y git neovim zsh
{{ end -}}
{{ end -}}
