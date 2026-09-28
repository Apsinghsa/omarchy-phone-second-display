#!/usr/bin/env bash
# phone-vnc-start — use an Android phone as a second Wayland display.
#
# Creates a headless Hyprland output, captures it with wayvnc, and tunnels the
# VNC port to the phone over USB with `adb reverse`.
#
# On the phone, connect an AVNC client to 127.0.0.1:5900 (no password: the
# server only listens on loopback, reachable solely through the USB tunnel).
#
# Config (all optional):
#   PHONE_VNC_OUTPUT   headless output name            (default: phone)
#   PHONE_VNC_MODE     output mode                     (default: 2400x1080@60)
#   PHONE_VNC_SCALE    output scale                    (default: 2)
#   PHONE_VNC_POS      output position                 (default: auto)
#   PHONE_VNC_PORT     VNC port on the phone           (default: 5900)
#   PHONE_VNC_SOCK     wayvnc unix socket              (default: /tmp/phone-vnc.sock)
#   PHONE_VNC_PRIMARY  primary output to anchor against(default: auto)

set -euo pipefail

OUTPUT="${PHONE_VNC_OUTPUT:-phone}"
MODE="${PHONE_VNC_MODE:-2400x1080@60}"
SCALE="${PHONE_VNC_SCALE:-2}"
PORT="${PHONE_VNC_PORT:-5900}"
SOCK="${PHONE_VNC_SOCK:-/tmp/phone-vnc.sock}"

log() { printf '[phone-vnc] %s\n' "$*"; }
die() { printf '[phone-vnc] error: %s\n' "$*" >&2; exit 1; }

for cmd in hyprctl wayvnc adb; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing '$cmd' — see README for install commands"
done

# --- already running? -------------------------------------------------------
if pgrep -f "[w]ayvnc -o $OUTPUT " >/dev/null 2>&1; then
  log "wayvnc is already capturing output '$OUTPUT' — nothing to do"
  exit 0
fi

# --- recreate the headless output if it survived a crash --------------------
if hyprctl monitors -j 2>/dev/null | grep -q "\"name\": *\"$OUTPUT\""; then
  log "reusing existing headless output '$OUTPUT'"
else
  hyprctl output create headless "$OUTPUT" >/dev/null || die "could not create headless output"
  log "created headless output '$OUTPUT'"
fi

# --- size it ----------------------------------------------------------------
# Quattro parses Hyprland's Lua config, so `hyprctl keyword monitor` is
# disabled; hl.monitor via `hyprctl eval` is the supported runtime idiom.
#
# Position is auto-computed unless PHONE_VNC_POS is set: the phone box is placed
# flush against the right edge of the focused monitor and centred vertically.
# Scale is NOT auto-computed — Hyprland quantises fractional values anyway, and
# a gap between outputs stops the mouse crossing, so PHONE_VNC_SCALE is used
# exactly as given.
if [ -n "${PHONE_VNC_POS:-}" ]; then
  POS="$PHONE_VNC_POS"
else
  # NOTE: pass values as argv, not as `VAR=x cmd | python3` — an env prefix
  # applies only to the first command in a pipeline, so python would never see
  # them.
  POS="$(hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
mode, scale, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
mons = json.load(sys.stdin)
primary = next((m for m in mons if m.get("focused")), None) or (mons[0] if mons else None)
if not primary or primary.get("name") == out:
    print("0x0"); raise SystemExit
mode_h = int(mode.split("@")[0].split("x")[1])
x = primary["x"] + primary["width"]
y = primary["y"] + max(0, int((primary["height"] - mode_h / scale) // 2))
print(f"{x}x{y}")
' "$MODE" "$SCALE" "$OUTPUT")"
fi

# Hyprland quantises fractional scale — read the effective value back rather
# than trusting what we asked for.
EFFECTIVE_SCALE="$(hyprctl monitors -j | python3 -c '
import json, sys
for m in json.load(sys.stdin):
    if m.get("name") == "'"$OUTPUT"'":
        print(m.get("scale", 1)); break
else:
    print(1)
')"

hyprctl eval "hl.monitor({ output=\"$OUTPUT\", mode=\"$MODE\", position=\"$POS\", scale=$SCALE })" >/dev/null \
  || die "could not size output '$OUTPUT'"
log "output '$OUTPUT' at $MODE scale=$SCALE (effective $EFFECTIVE_SCALE) position=$POS"

# --- start the capture ------------------------------------------------------
# NOTE: the bar widget probes for the literal string "wayvnc -o $OUTPUT " in
# the process cmdline, so keep -o/OUTPUT as the first two arguments.
wayvnc -o "$OUTPUT" -r -S "$SOCK" >/dev/null 2>&1 &
sleep 1
pgrep -f "[w]ayvnc -o $OUTPUT " >/dev/null 2>&1 || die "wayvnc failed to start (see $SOCK)"

# Verify it really is capturing *this* output, not a stale one.
if command -v wayvncctl >/dev/null 2>&1; then
  wayvncctl -S "$SOCK" output-list 2>/dev/null | grep -q '\*$' \
    && log "capture confirmed active" \
    || log "warning: capture is running but no active output reported"
fi
log "wayvnc listening on 127.0.0.1:$PORT"

# --- tunnel to the phone ----------------------------------------------------
# --remove takes ONE argument (tcp:5900), not the two-arg form.
adb reverse "tcp:$PORT" "tcp:$PORT" >/dev/null || die "adb reverse failed — is the phone connected?"
log "usb tunnel up: phone 127.0.0.1:$PORT -> desktop :$PORT"

cat <<EOF

  Display '$OUTPUT' is live.

    On the phone: open AVNC, connect to 127.0.0.1 port $PORT, no password.
    Move a window over:  hyprctl eval 'hl.dispatch(hl.dsp.window.move({ monitor = "$OUTPUT" }))'
    Move it back:       hyprctl eval 'hl.dispatch(hl.dsp.window.move({ monitor = "eDP-1" }))'
    Tear down:          phone-vnc-stop

EOF
