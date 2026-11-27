#!/bin/bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ITEM="${NAME:-secretive}"
SOCK="$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh"

if [ ! -d "/Applications/Secretive.app" ]; then
  sketchybar -m --set "$ITEM" drawing=off
  exit 0
fi

UID_NUM="$(id -u)"

if [ ! -S "$SOCK" ] || ! pgrep -u "$UID_NUM" -f "Secretive.SecretAgent" >/dev/null 2>&1; then
  sketchybar -m --set "$ITEM" \
    drawing=on \
    icon="" \
    icon.color=0xffBF616A \
    label="OFF" \
    label.drawing=on \
    label.color=0xffBF616A
  exit 0
fi

MUX_COUNT="$(pgrep -u "$UID_NUM" -f 'ssh: .*/\.ssh/cm/.* \[mux\]' 2>/dev/null | wc -l | tr -d ' ')"

if [ "${MUX_COUNT:-0}" -gt 0 ]; then
  sketchybar -m --set "$ITEM" \
    drawing=on \
    icon="" \
    icon.color=0xffA3BE8C \
    label="${MUX_COUNT}" \
    label.drawing=on \
    label.color=0xffECEFF4
else
  sketchybar -m --set "$ITEM" \
    drawing=on \
    icon="" \
    icon.color=0xffEBCB8B \
    label="SSH" \
    label.drawing=on \
    label.color=0xffD8DEE9
fi
