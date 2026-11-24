#!/bin/bash
set -euo pipefail

DIR="$HOME/.config/aerospace"
SRC="$DIR/secretive_focus_helper.swift"
BIN="$DIR/secretive_focus_helper"
STAMP="$DIR/.secretive_focus_helper.sha256"
LOG="$HOME/Library/Logs/secretive-focus-helper.log"

if [ ! -f "$SRC" ]; then
    exit 0
fi

CUR_HASH="$(/usr/bin/shasum -a 256 "$SRC" | awk '{print $1}')"
OLD_HASH=""
if [ -f "$STAMP" ]; then
    OLD_HASH="$(cat "$STAMP" 2>/dev/null || true)"
fi

if [ ! -x "$BIN" ] || [ "$CUR_HASH" != "$OLD_HASH" ] || [ "$SRC" -nt "$BIN" ] || [ "${1:-}" = "--force" ]; then
    mkdir -p "$(dirname "$LOG")"
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT
    if /usr/bin/swiftc -O \
        -F /System/Library/PrivateFrameworks \
        -framework SkyLight \
        -framework Cocoa \
        -framework ApplicationServices \
        "$SRC" -o "$TMP_DIR/secretive_focus_helper" >>"$LOG" 2>&1; then
        /usr/bin/codesign -fs - --identifier com.cayco.secretive-focus-helper "$TMP_DIR/secretive_focus_helper" >>"$LOG" 2>&1 || true
        mv -f "$TMP_DIR/secretive_focus_helper" "$BIN"
        printf '%s\n' "$CUR_HASH" > "$STAMP"
        pkill -fx "$BIN" 2>/dev/null || pkill -x secretive_focus_helper 2>/dev/null || true
        sleep 0.2
    else
        echo "[$(date -Iseconds)] Failed to compile secretive_focus_helper.swift" >>"$LOG"
        exit 1
    fi
    rm -rf "$TMP_DIR"
    trap - EXIT
fi

if pgrep -fx "$BIN" >/dev/null 2>&1; then
    exit 0
fi

nohup "$BIN" >>"$LOG" 2>&1 </dev/null &
disown 2>/dev/null || true
