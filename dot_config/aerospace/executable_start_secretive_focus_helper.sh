#!/bin/bash
set -euo pipefail

DIR="$HOME/.config/aerospace"
SRC="$DIR/secretive_focus_helper.swift"
BIN="$DIR/secretive_focus_helper"

if [ ! -f "$SRC" ]; then
    exit 0
fi

if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
    /usr/bin/swiftc -O \
        -F /System/Library/PrivateFrameworks \
        -framework SkyLight \
        -framework Cocoa \
        -framework ApplicationServices \
        "$SRC" -o "$BIN.tmp"
    mv -f "$BIN.tmp" "$BIN"
    pkill -fx "$BIN" 2>/dev/null || true
fi

if pgrep -fx "$BIN" >/dev/null 2>&1; then
    exit 0
fi

nohup "$BIN" >/dev/null 2>&1 </dev/null &
disown 2>/dev/null || true
