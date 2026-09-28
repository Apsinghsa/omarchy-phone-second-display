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

To remove it:

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

## Known limitation: the start/stop scripts

The widget's **Start** and **Stop** buttons shell out to two helper scripts:

```
/home/apsingh/.local/bin/phone-vnc-start
/home/apsingh/.local/bin/phone-vnc-stop
```

Those paths are hardcoded and specific to the machine this was developed on. If you
clone this repo, install your own scripts at those paths or edit `startService()` and
`stopService()` in `Widget.qml` to point at yours. The bar icon, status polling and
panel all work without them — only the Start/Stop buttons depend on the scripts.

## Files

| File | Role |
| --- | --- |
| `manifest.json` | Plugin manifest — id, entry points, bar widget metadata |
| `Widget.qml` | Bar button, 3s status poll, start/stop service control |
| `Panel.qml` | Drawer panel — status line, Start/Stop buttons, usage hint |

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
