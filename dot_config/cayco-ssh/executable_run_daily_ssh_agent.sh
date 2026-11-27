#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

DIR="$HOME/.config/cayco-ssh"
SRC="$DIR/cayco_daily_ssh_agent.swift"
APP="$DIR/CaycoDailySSH.app"
BIN="$APP/Contents/MacOS/CaycoDailySSH"
PLIST="$APP/Contents/Info.plist"
RES="$APP/Contents/Resources"
STAMP="$DIR/.cayco_daily_ssh_agent.sha256"

CUR_HASH="$(/usr/bin/shasum -a 256 "$SRC" | awk '{print $1}')"
OLD_HASH="$(cat "$STAMP" 2>/dev/null || true)"

if [ ! -x "$BIN" ] || [ "$CUR_HASH" != "$OLD_HASH" ] || [ "$SRC" -nt "$BIN" ]; then
  TMP_APP="$(mktemp -d)/CaycoDailySSH.app"
  mkdir -p "$TMP_APP/Contents/MacOS" "$TMP_APP/Contents/Resources"
  cat > "$TMP_APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.cayco.daily-ssh-agent</string>
    <key>CFBundleName</key>
    <string>Cayco SSH (24h)</string>
    <key>CFBundleDisplayName</key>
    <string>Cayco SSH (24h)</string>
    <key>CFBundleExecutable</key>
    <string>CaycoDailySSH</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
  if [ -f "/Applications/Secretive.app/Contents/Resources/AppIcon.icns" ]; then
    cp -f "/Applications/Secretive.app/Contents/Resources/AppIcon.icns" "$TMP_APP/Contents/Resources/AppIcon.icns"
  fi
  /usr/bin/swiftc -O \
    -framework LocalAuthentication \
    -framework Foundation \
    "$SRC" -o "$TMP_APP/Contents/MacOS/CaycoDailySSH"
  /usr/bin/codesign --force --deep --sign - --identifier com.cayco.daily-ssh-agent "$TMP_APP" >/dev/null 2>&1 || true
  rm -rf "$APP"
  mv "$TMP_APP" "$APP"
  printf '%s\n' "$CUR_HASH" > "$STAMP"
fi

exec "$BIN"
