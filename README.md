# xeneonctl

A tiny command-line tool for controlling screen settings — brightness,
contrast, volume, mute, input — on a CORSAIR XENEON EDGE, without
installing iCUE or any other bloated app.

Runs on **macOS (Apple Silicon)** and **Windows**. It should also work
with any other DDC/CI-capable external display, since it just speaks
standard DDC/CI (VESA MCCS) to whatever panel it finds.

## How it works

DDC/CI is a standard side-channel that lets a computer read and write a
monitor's on-screen-display settings over the video cable. Each platform
exposes it differently, so there's one small source file per platform and
the `Makefile` picks the right one automatically:

- **macOS** ([`src/xeneonctl.m`](src/xeneonctl.m)) — talks to USB-C /
  DisplayPort Alt Mode displays through Apple's private `IOAVService`
  API. This is the same technique used by
  [m1ddc](https://github.com/waydabber/m1ddc),
  [AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) and
  [MonitorControl](https://github.com/MonitorControl/MonitorControl);
  this project reimplements just the small slice needed to control one
  display from the command line.
  **Requires an Apple Silicon Mac.** It does not support Intel Macs or
  the built-in HDMI port on some Apple Silicon models (use
  [BetterDisplay](https://github.com/waydabber/BetterDisplay) for that).

- **Windows** ([`src/xeneonctl.c`](src/xeneonctl.c)) — uses the standard
  Monitor Configuration API (`Dxva2.dll`), which is public and has
  shipped with Windows since Vista. No private APIs needed.

Either way: no kernel extensions, no drivers, no daemons, no third-party
libraries.

## Install

**macOS** — requires the Xcode Command Line Tools
(`xcode-select --install` if you don't already have them).

**Windows** — requires `make` and a C compiler. The easiest way to get
both is [MSYS2](https://www.msys2.org/) or
[w64devkit](https://github.com/skeeto/w64devkit); either gives you
`make` and MinGW-w64 `gcc` in one install.

The commands are the same on both platforms:

```sh
git clone <this-repo-url>
cd xeneon_ctl
make
make install
```

On macOS `make install` puts the binary in `/usr/local/bin` and will
prompt for your password. On Windows it installs to
`%LOCALAPPDATA%\Programs\xeneonctl` and prints a reminder to add that
folder to your `PATH`.

Installing is optional — `make` on its own builds the binary in place and
you can run it from there.

## Usage

```sh
xeneonctl list                    # see what displays were detected
xeneonctl get brightness          # -> "95 (max 100)"
xeneonctl set brightness 60
xeneonctl set contrast 50
xeneonctl set mute on
xeneonctl get volume
```

By default it targets the first connected display whose name contains
"XENEON"; if none is found it falls back to the first external display it
can find. Pass `-v` to see which display it picked:

```sh
xeneonctl -v get brightness
```

Available settings: `brightness`, `contrast`, `volume`, `mute`, `input`.

## Uninstall

```sh
make uninstall
```

## GUI

A very small window with three sliders (brightness, contrast, volume), if
you'd rather not use the command line. It just shells out to the
`xeneonctl` binary above.

```sh
make gui
```

This builds the CLI first, then launches the GUI for your platform —
SwiftUI on macOS ([`gui/`](gui/)), WinForms on Windows
([`gui-windows/`](gui-windows/)). The Windows GUI needs the
[.NET SDK](https://dotnet.microsoft.com/download) (8.0 or newer).

## Stuck-touch-after-sleep fix (macOS only)

The Xeneon Edge has a known quirk where its touchscreen can get "stuck"
in a pressed state after your Mac wakes from sleep, blocking clicks until
you tap the panel once. There's an optional background helper that
automates that tap on every wake — see [`wakefix/`](wakefix/README.md).

This works around an Apple-specific sleep/wake behaviour and has no
Windows equivalent; `make wakefix` is a no-op there.
