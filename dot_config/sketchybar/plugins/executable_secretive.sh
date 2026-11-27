#!/bin/bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ITEM="${NAME:-secretive}"
SECRETIVE_SOCK="$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh"
DAILY_PLIST="$HOME/Library/LaunchAgents/com.cayco.daily-ssh-agent.plist"
DAILY_SOCK="$HOME/.ssh/cayco/daily-agent.sock"
STATE_FILE="$HOME/.ssh/cayco/.daily_unlock_state"

if [ ! -d "/Applications/Secretive.app" ]; then
  sketchybar -m --set "$ITEM" drawing=off
  exit 0
fi

UID_NUM="$(id -u)"

if [ ! -S "$SECRETIVE_SOCK" ] || ! pgrep -u "$UID_NUM" -f "Secretive.SecretAgent" >/dev/null 2>&1; then
  sketchybar -m --set "$ITEM" \
    drawing=on \
    icon="" \
    icon.color=0xffBF616A \
    label="OFF" \
    label.drawing=on \
    label.color=0xffBF616A
  exit 0
fi

if [ -f "$DAILY_PLIST" ]; then
  if [ ! -S "$DAILY_SOCK" ] || ! pgrep -u "$UID_NUM" -f "CaycoDailySSH" >/dev/null 2>&1; then
    sketchybar -m --set "$ITEM" \
      drawing=on \
      icon="" \
      icon.color=0xffBF616A \
      label="ERR" \
      label.drawing=on \
      label.color=0xffBF616A
    exit 0
  fi

  REM_LABEL=""
  if [ -f "$STATE_FILE" ]; then
    REM_LABEL="$(/usr/bin/python3 - "$STATE_FILE" 2>/dev/null <<'PY' || true
import json, subprocess, sys, time
st = json.load(open(sys.argv[1]))
out = subprocess.check_output(["/usr/sbin/sysctl", "-n", "kern.boottime"], text=True)
boot_sec = int(out.split("sec =")[1].split(",")[0].strip())
rem = int(st.get("unlocked_until", 0) - time.time())
if st.get("boot_sec") == boot_sec and rem > 0:
    print(f"{(rem + 3599) // 3600}h" if rem >= 3600 else f"{max(1, rem // 60)}m")
PY
)"
  fi

  if [ -n "$REM_LABEL" ]; then
    sketchybar -m --set "$ITEM" \
      drawing=on \
      icon="" \
      icon.color=0xffA3BE8C \
      label="$REM_LABEL" \
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
  exit 0
fi

# Fallback for Macs without DailySSHGate (e.g. MacBook Air): show live mux count
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
