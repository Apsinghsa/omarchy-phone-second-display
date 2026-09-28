#!/usr/bin/env python3
"""Compute where to place the phone headless output.

Reads `hyprctl monitors -j` on stdin and prints four space-separated fields:

    <phone_pos> <primary_mode> <primary_pos> <primary_scale>

Two Hyprland behaviours drive the whole design:

1. Any output with no explicit position in the config is AUTO-LAYOUT by
   Hyprland, and auto-layout slots those AFTER manually-positioned outputs. So
   placing the phone alone displaces the laptop panel and the phone lands on
   the wrong side. We therefore also emit the primary's current
   mode/position/scale so the caller can re-pin it and stop the drift.

2. Geometry must be compared in LOGICAL pixels (width / scale), never mode
   pixels. A 1920x1080 panel at scale 1.25 is 1536x864 logical; centring
   against 1080 leaves the phone hanging below the laptop.

The phone is placed flush against the primary's right edge (gap 0), which is
what lets the mouse cross between the two outputs, and centred vertically.
"""
import json
import sys


def main() -> None:
    mode_arg, scale_arg, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]

    try:
        mons = json.load(sys.stdin)
    except (ValueError, OSError):
        print("0x0 0x0 0x0 1")
        return
    if not isinstance(mons, list):
        mons = []

    # The primary is the first real output that is not the phone and not
    # disabled. Deliberately not "focused": focus moves between outputs, and
    # anchoring layout to whatever happens to be focused is unstable.
    primary = next(
        (m for m in mons if m.get("name") != out and not m.get("disabled")), None
    )
    if primary is None or primary.get("name") == out:
        print("0x0 0x0 0x0 1")
        return

    p_scale = float(primary.get("scale") or 1)
    p_logical_w = primary["width"] / p_scale
    p_logical_h = primary["height"] / p_scale

    try:
        phone_w, phone_h = (int(v) for v in mode_arg.split("@")[0].split("x"))
    except ValueError:
        phone_w = phone_h = 0

    x = primary["x"] + p_logical_w
    y = primary["y"] + max(0, int((p_logical_h - phone_h / scale_arg) // 2))

    primary_mode = "{}x{}@{}".format(
        primary["width"], primary["height"], primary.get("refreshRate", 60)
    )
    primary_pos = "{}x{}".format(primary["x"], primary["y"])

    print(
        "{}x{} {} {} {}".format(
            int(x), int(y), primary_mode, primary_pos, p_scale
        )
    )


if __name__ == "__main__":
    main()
