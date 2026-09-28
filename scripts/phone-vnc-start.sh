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

for cmd in hyprctl wayvnc adb python3; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing '$cmd' — see README for install commands (pacman -S --needed ...)"
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

# --- pin the primary, then size the phone -----------------------------------
# Quattro parses Hyprland's Lua config, so `hyprctl keyword monitor` is
# disabled; hl.monitor via `hyprctl eval` is the supported runtime idiom.
#
# The position maths (including why the primary must be re-pinned) lives in
# scripts/poscalc.py. Resolve symlinks first: this script is normally invoked
# through ~/.local/bin, so ${BASH_SOURCE[0]} would point at the symlink and
# dirname would give the wrong directory.
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
POSCALC="$(dirname "$SELF")/poscalc.py"
[ -f "$POSCALC" ] || die "poscalc.py not found next to this script ($POSCALC)"

read -r POS PIN_MODE PIN_POS PIN_SCALE PIN_NAME < <(
  hyprctl monitors -j 2>/dev/null | python3 "$POSCALC" "$MODE" "$SCALE" "$OUTPUT"
)

# Re-assert the primary's own mode/position/scale. Without this, Hyprland's
# auto-layout displaces the laptop panel every time the phone is placed, and
# successive runs walk the whole desktop sideways. Best-effort: if this fails
# we still place the phone and verify the result below.
if [ -n "${PIN_NAME:-}" ] && [ -n "${PHONE_VNC_POS:-}" = "" ]; then
  hyprctl eval "hl.monitor({ output=\"$PIN_NAME\", mode=\"$PIN_MODE\", position=\"$PIN_POS\", scale=$PIN_SCALE })" \
    >/dev/null 2>&1 || true
  sleep 0.3
fi

# An explicit PHONE_VNC_POS overrides the computed position entirely.
[ -n "${PHONE_VNC_POS:-}" ] && POS="$PHONE_VNC_POS"

hyprctl eval "hl.monitor({ output=\"$OUTPUT\", mode=\"$MODE\", position=\"$POS\", scale=$SCALE })" >/dev/null \
  || die "could not size output '$OUTPUT'"

# Read the EFFECTIVE geometry back rather than trusting what we asked for.
# Hyprland quantises fractional scales, and the apply is async, so give it a
# moment before reading. Both width/height in `monitors -j` are MODE pixels —
# divide by scale to get the logical box.
sleep 0.5
EFFECTIVE="$(hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
want = sys.argv[1]
for m in json.load(sys.stdin):
    if m.get("name") == want:
        s = float(m.get("scale") or 1)
        w, h = int(m["width"] / s), int(m["height"] / s)
        print("%dx%d logical, scale %s" % (w, h, m.get("scale")))
        break
else:
    print("not found")
' "$OUTPUT")"
log "output '$OUTPUT' at $MODE position=$POS -> $EFFECTIVE"

# --- start the capture ------------------------------------------------------
# NOTE: the bar widget probes for the literal string "wayvnc -o $OUTPUT " in
# the process cmdline, so keep -o/OUTPUT as the first two arguments.
wayvnc -o "$OUTPUT" -r -S "$SOCK" >/dev/null 2>&1 &
sleep 1
pgrep -f "[w]ayvnc -o $OUTPUT " >/dev/null 2>&1 || die "wayvnc failed to start (see $SOCK)"

# Verify it really is capturing THIS output, not a stale one. wayvncctl marks
# the active line with a leading '*' and the line ends in ')', so match the
# start of the line — matching a trailing '*' silently always fails.
if command -v wayvncctl >/dev/null 2>&1; then
  active="$(wayvncctl -S "$SOCK" output-list 2>/dev/null | sed -n 's/^\* *//p' | cut -d: -f1)"
  case "$active" in
    "$OUTPUT"|"$OUTPUT ") log "capture confirmed active on '$OUTPUT'" ;;
    "")                  log "warning: capture running but wayvncctl reported no active output" ;;
    *)                   log "warning: capturing '$active', not '$OUTPUT'" ;;
  esac
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
