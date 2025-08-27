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
    4  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"\n
    5  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k\n
    6  git clone --depth=1 https://github.com/romkatv/powerlevel10k-media.git ~/powerlevel10k-media\n
    7  sudo mkdir -p /usr/share/fonts/truetype/meslo\nsudo cp ~/powerlevel10k-media/*.ttf /usr/share/fonts/truetype/meslo/\nsudo fc-cache -fv\n
    8  sudo apt update\nsudo apt install fonts-powerline\n
    9  sudo apt install fzf thefuck zoxide
   10  ls ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
   11  sudo apt install eza
   12  snap install eza
   13  snap inst
   14  sudo snap install eza
   15  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \\n  | sudo gpg --dearmor -o /etc/apt/keyrings/eza.gpg\necho "deb [signed-by=/etc/apt/keyrings/eza.gpg] http://deb.gierens.de stable main" \\n  | sudo tee /etc/apt/sources.list.d/eza.list
   16  sudo apt update\n
   17  sudo apt install -y eza\n
   18  ls ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
   19  sudo apt install bat
   20  sudo apt install fzf
