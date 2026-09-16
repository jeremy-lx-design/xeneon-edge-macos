# xeneonctl

A tiny command-line tool for controlling screen settings — brightness,
contrast, volume, mute, input — on a CORSAIR XENEON EDGE connected over
USB-C, without installing iCUE or any other bloated app.

It should also work with any other DDC/CI-capable external display
connected via USB-C / DisplayPort Alt Mode, since it just speaks
standard DDC/CI (VESA MCCS) to whatever panel it finds.

## How it works

macOS can talk DDC/CI to USB-C/DisplayPort Alt Mode displays on Apple
Silicon through a private `IOAVService` API. `xeneonctl` uses that API
directly — no kernel extensions, no daemons, no third-party libraries.
This is the same technique used by tools like
[m1ddc](https://github.com/waydabber/m1ddc),
[AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC), and
[MonitorControl](https://github.com/MonitorControl/MonitorControl); this
project reimplements just the small slice of it needed to control one
display from the command line.

**Requires an Apple Silicon Mac.** It does not support Intel Macs or the
built-in HDMI port on some Apple Silicon models (use
[BetterDisplay](https://github.com/waydabber/BetterDisplay) for that).

## Install

Requires the Xcode Command Line Tools (`xcode-select --install` if you
don't already have them). No other dependencies.

```sh
git clone <this-repo-url>
cd xeneon_ctl
make
sudo make install   # installs to /usr/local/bin
```

Or just build it and run it in place with `make` — installing system-wide
is optional.

## Usage

```sh
xeneonctl list                    # see what displays were detected
xeneonctl get brightness          # -> "95 (max 100)"
xeneonctl set brightness 60
xeneonctl set contrast 50
xeneonctl set mute on
xeneonctl get volume
```

By default it targets the first connected external display whose name
contains "XENEON"; if none is found it falls back to the first non-built-in
display it can find. Pass `-v` to see which display it picked:

```sh
xeneonctl -v get brightness
```

Available settings: `brightness`, `contrast`, `volume`, `mute`, `input`.

## Uninstall

```sh
sudo make uninstall
```

## GUI

A very small window with three sliders (brightness, contrast, volume), if
you'd rather not use the command line. It just shells out to the `xeneonctl`
binary above, so build that first.

```sh
make            # build ./xeneonctl (the GUI shells out to it)
cd gui
swift run
```

## Stuck-touch-after-sleep fix (optional)

The Xeneon Edge has a known quirk where its touchscreen can get "stuck" in
a pressed state after your Mac wakes from sleep, blocking clicks until you
tap the panel once. There's an optional background helper that automates
that tap on every wake — see [`wakefix/`](wakefix/README.md).
