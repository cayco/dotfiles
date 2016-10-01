# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=10000000
SAVEHIST=10000000
bindkey -e
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename '/Users/cayco/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall

source antigen.zsh
antigen use oh-my-zsh
antigen theme gnzh
antigen bundle zsh-users/zsh-completions src
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle brew
antigen bundle brew-cask
antigen bundle gem
antigen bundle osx
antigen bundle autojump
antigen bundle common-aliases

antigen-apply


# Path for homebrew (/usr/local/[s]bin)

PATH=/usr/local/bin:/usr/local/sbin:$PATH

# Set up rbenv for Homebrew. Make sure path is BEFORE Homebrew's /usr/local/[s]bin
#To enable shims and autocompletion add to your profile:
if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi

setopt HIST_IGNORE_DUPS
setopt INC_APPEND_HISTORY
# set -o vi
source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fpath=(/usr/local/share/zsh-completions $fpath)

# Vi mode configuration
bindkey -v
bindkey '\eOH'  beginning-of-line
bindkey '\eOF'  end-of-line
export KEYTIMEOUT=1

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"
#
# # Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

