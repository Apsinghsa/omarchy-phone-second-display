# Phone Second Display (VNC) — Omarchy bar widget

An [Omarchy](https://omarchy.org/) bar widget that turns an Android phone into a
genuine second monitor for your Hyprland desktop — headless output, captured with
WayVNC and tunnelled over USB.

Click the bar icon to open a panel with Start/Stop and live status. The bar icon
reflects whether the VNC stream is up, polled every 3 seconds.

The stack:

1. `hyprctl output create headless phone` — a virtual output with no physical screen
2. `hyprctl eval 'hl.monitor({...})'` — sized and positioned it
3. `wayvnc -o phone` — captures that output, listens on `127.0.0.1:5900`
4. `adb reverse tcp:5900 tcp:5900` — tunnels it to the phone over USB

On the phone, connect any VNC client to `127.0.0.1:5900`. **No password is needed**,
and that is deliberate: the server only ever binds to localhost and is reachable
solely through the USB tunnel, so it is never exposed to the network.

## Requirements

| Dependency | Arch package | Why |
| --- | --- | --- |
| `wayvnc` | `extra/wayvnc` | Captures the headless output |
| `adb` | `extra/android-tools` | USB tunnel to the phone |
| `hyprctl` | ships with Hyprland | Creates and sizes the headless output |
| A VNC client on the phone | e.g. [AVNC](https://play.google.com/store/apps/details?id=com.gaurav.avnc) | Displays the stream |

Install the dependencies:

```bash
sudo pacman -S wayvnc android-tools
```

On the phone: enable **USB debugging** in Developer Options, plug it in, and accept
the RSA prompt. Confirm with:

```bash
adb devices -l
```

## Install

```bash
omarchy plugin add https://github.com/Apsinghsa/omarchy-phone-second-display
```

Then restart the shell so the compiled bar widget is picked up:

```bash
omarchy restart shell
```

A compiled third-party bar widget does **not** hot-reload — `omarchy-shell
rescanPlugins` will not replace already-compiled code, so the restart is required.

### Install the helper scripts

Start/Stop shell out to `~/.local/bin/phone-vnc-start` and
`~/.local/bin/phone-vnc-stop`. Link them from the cloned plugin directory — no
path editing needed:

```bash
~/.config/omarchy/plugins/apsingh.phone-vnc/scripts/install.sh
```

or by hand:

```bash
mkdir -p ~/.local/bin
ln -sf ~/.config/omarchy/plugins/apsingh.phone-vnc/scripts/phone-vnc-{start,stop}.sh \
        ~/.local/bin/
```

To remove the plugin:

```bash
omarchy plugin remove apsingh.phone-vnc
```

## Usage

1. Click the display icon in the bar to open the panel.
2. **Start phone display** — enabled only while the stream is down. Brings up the
   headless output, sized and positioned next to your laptop panel.
3. Open your VNC client on the phone and connect to `127.0.0.1:5900`.
4. **Stop phone display** — tears the output, server and tunnel down.

## Quattro note: `hyprctl keyword` is disabled

Omarchy Quattro ships Hyprland with the **Lua config parser**, so the classic
`hyprctl keyword monitor ...` fails with *"keyword can't work with non-legacy
parsers"*. The scripts use the Quattro-native `hl` API instead:

```bash
hyprctl output create headless phone
hyprctl eval 'hl.monitor({ output="phone", mode="2400x1080@60", position="0x0", scale=2 })'
```

Window moves use the same API, because `hyprctl dispatch movewindowtomonitor` silently
no-ops on the Lua build:

```bash
hyprctl eval 'hl.dispatch(hl.dsp.window.move({ monitor="phone" }))'
```

## The helper scripts

### `phone-vnc-start`

1. Reuses or creates the headless output `phone`
2. Sizes it via `hl.monitor` (see the Quattro note above)
3. Starts `wayvnc -o phone -r -S $SOCK`, which binds `127.0.0.1:5900`
4. Runs `adb reverse tcp:5900 tcp:5900` to open the USB tunnel

The output is placed flush against the right edge of your primary monitor and
centred vertically, so the mouse crosses onto the phone without falling into a
gap. Hyprland quantises fractional scales, so the script reads the *effective*
scale back rather than trusting what it asked for.

Two Hyprland behaviours make this less trivial than it looks, and both are
handled in `scripts/poscalc.py`:

- **Auto-layout displaces unpositioned outputs.** Any monitor with no explicit
  position in your config is auto-placed by Hyprland, *after* manually
  positioned ones. So placing the phone alone pushes your laptop panel sideways,
  and each successive run walks the whole desktop further off. The script
  re-pins the primary's own mode/position/scale before placing the phone.
- **Geometry is logical, not mode, pixels.** A 1920x1080 panel at scale 1.25 is
  1536x864 logical. Centring against the mode height instead leaves the phone
  hanging below the laptop.

With a 1920x1080 laptop at scale 1.25 and the phone at 2400x1080 scale 2, the
result is `phone @ 1536x162` — a 1200x540 box, gap 0, vertically centred.
Repeated runs are stable.

You can also drive it directly:

```bash
phone-vnc-start   # bring the display up
phone-vnc-stop    # tear it down
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `PHONE_VNC_OUTPUT` | `phone` | headless output name |
| `PHONE_VNC_MODE` | `2400x1080@60` | output mode — use `1080x2400@60` for portrait |
| `PHONE_VNC_SCALE` | `2` | logical scale |
| `PHONE_VNC_POS` | auto | `XxY` position override |
| `PHONE_VNC_PORT` | `5900` | VNC port, forwarded to the phone |
| `PHONE_VNC_SOCK` | `/tmp/phone-vnc.sock` | wayvnc control socket |

### `phone-vnc-stop`

Order matters, and it is not cosmetic: **wayvnc is stopped before the headless
output is removed.** If you remove the output first, the phone keeps showing a
frozen mirror of your desktop — it holds the last frame it was sent.

Then the USB tunnel is dropped and the socket is removed. Safe to run when
nothing is up.

## Moving windows

Window moves use the same Quattro `hl` API, because
`hyprctl dispatch movewindowtomonitor` silently no-ops on the Lua build:

```bash
# active window to the phone
hyprctl eval 'hl.dispatch(hl.dsp.window.move({ monitor = "phone" }))'
# a specific app to the phone
hyprctl eval 'hl.dispatch(hl.dsp.window.move({ monitor = "phone", window = "class:okular" }))'
# back to the laptop
hyprctl eval 'hl.dispatch(hl.dsp.window.move({ monitor = "eDP-1" }))'
# move the keyboard/workspace focus to the phone
hyprctl eval 'hl.dispatch(hl.dsp.focus({ monitor = "phone" }))'
```

To control the phone from the PC mouse, cross onto the phone's logical box and
warp the cursor over explicitly if needed:

```bash
hyprctl eval 'hl.dispatch(hl.dsp.cursor.move({ x = 2400, y = 432 }))'
```

## Files

| File | Role |
| --- | --- |
| `manifest.json` | Plugin manifest — id, entry points, bar widget metadata |
| `Widget.qml` | Bar button, 3s status poll, start/stop service control |
| `Panel.qml` | Drawer panel — status line, Start/Stop buttons, usage hint |
| `scripts/phone-vnc-start.sh` | Creates the headless output, starts wayvnc, opens the tunnel |
| `scripts/phone-vnc-stop.sh` | Tears down server, tunnel and output in the correct order |
| `scripts/poscalc.py` | Position maths — places the phone flush against the laptop panel |
| `scripts/install.sh` | Links both scripts into `~/.local/bin` |

## How the status probe works

Every 3 seconds the widget runs a single shell command:

```sh
pgrep -f '[w]ayvnc -o phone '   # is the capture alive?
```

The `[w]` bracket is deliberate — without it the pattern matches `pgrep`'s own command
line and the check always reports true. The trailing space matters too, so the pattern
does not match other WayVNC outputs on other monitors.

## License

MIT — see [LICENSE](LICENSE).
