#!/usr/bin/env bash
# phone-vnc-stop — tear down the phone second display created by
# phone-vnc-start.sh. Safe to run when nothing is up.
#
# Order matters: wayvnc must be stopped BEFORE the headless output is removed.
# If you remove the output first, the phone keeps displaying a frozen mirror of
# your desktop (it holds the last frame it received).

set -uo pipefail

OUTPUT="${PHONE_VNC_OUTPUT:-phone}"
PORT="${PHONE_VNC_PORT:-5900}"
SOCK="${PHONE_VNC_SOCK:-/tmp/phone-vnc.sock}"

log() { printf '[phone-vnc] %s\n' "$*"; }

# --- 1. stop the capture, before touching the output ------------------------
if pgrep -f "[w]ayvnc -o $OUTPUT " >/dev/null 2>&1; then
  pkill -f "[w]ayvnc -o $OUTPUT " 2>/dev/null && log "stopped wayvnc"
  sleep 1
  pgrep -f "[w]ayvnc -o $OUTPUT " >/dev/null 2>&1 && {
    pkill -9 -f "[w]ayvnc -o $OUTPUT " 2>/dev/null
    sleep 1
  }
else
  log "wayvnc was not running"
fi

# --- 2. drop the USB tunnel (single-arg form) -------------------------------
if command -v adb >/dev/null 2>&1 && adb devices 2>/dev/null | grep -q 'device$'; then
  adb reverse --remove "tcp:$PORT" >/dev/null 2>&1 && log "removed usb tunnel tcp:$PORT"
else
  log "skipping tunnel removal (no adb device connected)"
fi

# --- 3. remove the headless output ------------------------------------------
if hyprctl monitors -j 2>/dev/null | grep -q "\"name\": *\"$OUTPUT\""; then
  hyprctl output remove "$OUTPUT" >/dev/null 2>&1 \
    && log "removed headless output '$OUTPUT'" \
    || log "could not remove output '$OUTPUT'"
else
  log "output '$OUTPUT' was not present"
fi

rm -f "$SOCK" 2>/dev/null
log "done"
