#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$HOME/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="/usr/bin/false"

CHEZMOI_SRC="$HOME/.local/share/chezmoi"
LOCK_DIR="/tmp/chezmoi-auto-sync-$(id -u).lock"

if ! command -v chezmoi >/dev/null 2>&1 || [ ! -d "$CHEZMOI_SRC/.git" ]; then
    exit 0
fi

# Stale lock cleanup (>10 minutes)
if [ -d "$LOCK_DIR" ]; then
    if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +10 2>/dev/null || true)" ]; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

# Never interfere while user or agent has uncommitted work in chezmoi source
if [ -n "$(git -C "$CHEZMOI_SRC" status --porcelain 2>/dev/null || true)" ]; then
    exit 0
fi

# Fetch over HTTPS only (cayco/dotfiles is public -> zero Secretive/SSH prompts)
if ! git -C "$CHEZMOI_SRC" -c url."https://github.com/".insteadOf="git@github.com:" fetch origin master --quiet 2>/dev/null; then
    exit 0
fi

LOCAL_SHA="$(git -C "$CHEZMOI_SRC" rev-parse HEAD)"
REMOTE_SHA="$(git -C "$CHEZMOI_SRC" rev-parse origin/master)"

PULLED=0
if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
    if git -C "$CHEZMOI_SRC" merge-base --is-ancestor "$LOCAL_SHA" "$REMOTE_SHA" 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fast-forwarding chezmoi ${LOCAL_SHA:0:7} -> ${REMOTE_SHA:0:7}"
        git -C "$CHEZMOI_SRC" merge --ff-only origin/master --quiet
        PULLED=1
    else
        # Local branch is ahead or diverged; do not touch
        exit 0
    fi
fi

STATUS_FILES="$(chezmoi status --exclude=scripts 2>/dev/null || true)"
STATUS_SCRIPTS="$(chezmoi status --include=scripts 2>/dev/null || true)"

if [ "$PULLED" -eq 0 ] && [ -z "$STATUS_FILES" ] && [ -z "$STATUS_SCRIPTS" ]; then
    exit 0
fi

if [ -n "$STATUS_FILES" ]; then
    SAFE_TARGETS=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        col1="${line:0:1}"
        col2="${line:1:1}"
        rel="${line:3}"
        if [ "$col1" = " " ] && [ "$col2" != " " ]; then
            SAFE_TARGETS+=("$HOME/$rel")
        elif [ "$col1" != " " ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Skipping locally modified file: ~/$rel ($col1$col2)"
        fi
    done <<< "$STATUS_FILES"

    if [ "${#SAFE_TARGETS[@]}" -gt 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Applying ${#SAFE_TARGETS[@]} updated dotfile(s)"
        chezmoi apply --no-tty --force --exclude=scripts "${SAFE_TARGETS[@]}"
    fi
fi

if [ -n "$STATUS_SCRIPTS" ] || [ "$PULLED" -eq 1 ]; then
    chezmoi apply --no-tty --include=scripts
fi

# Keep ~/github/dotfiles mirror fast-forwarded if present and clean
MIRROR_DIR="$HOME/github/dotfiles"
if [ -d "$MIRROR_DIR/.git" ] && [ -z "$(git -C "$MIRROR_DIR" status --porcelain 2>/dev/null || true)" ]; then
    git -C "$MIRROR_DIR" -c url."https://github.com/".insteadOf="git@github.com:" pull --ff-only origin master --quiet 2>/dev/null || true
fi
