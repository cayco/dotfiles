#!/bin/bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [ "${MODIFIER:-none}" = "cmd" ]; then
  "$HOME/.local/bin/cayco-ssh-unlock" --lock >/dev/null 2>&1 &
  exit 0
fi

if [ "${BUTTON:-left}" = "right" ] || [ "${MODIFIER:-none}" = "shift" ]; then
  nohup "$HOME/.local/bin/cayco-ssh-unlock" --unlock >/dev/null 2>&1 &
  exit 0
fi

FRONT_BID="$(/usr/bin/lsappinfo info -only bundleid "$(/usr/bin/lsappinfo front)" 2>/dev/null | sed -E 's/.*"CFBundleIdentifier"="([^"]*)".*/\1/' || true)"
if [ "$FRONT_BID" = "com.maxgoedjen.Secretive.Host" ]; then
  /usr/bin/osascript -e 'tell application "Secretive" to quit' >/dev/null 2>&1 || true
else
  /usr/bin/open -a Secretive
fi
