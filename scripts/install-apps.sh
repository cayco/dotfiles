#!/bin/bash

# Detect OS
OS=$(uname -s)

if [[ "$OS" == "Darwin" ]]; then
    # macOS installation
    if ! command -v brew &> /dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Find Brewfile location
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    REPO_DIR="$(dirname "$SCRIPT_DIR")"
    BREWFILE="$REPO_DIR/Brewfile"
    
    # If Brewfile doesn't exist, try Brewfile.tmpl
    if [[ ! -f "$BREWFILE" ]]; then
        BREWFILE="$REPO_DIR/Brewfile.tmpl"
    fi
    
    brew bundle --file="$BREWFILE" --verbose --force

elif [[ "$OS" == "Linux" ]]; then
    # Linux installation
    if [[ -f "/etc/os-release" ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            sudo apt update && sudo apt install -y git neovim zsh
        fi
    fi
fi
