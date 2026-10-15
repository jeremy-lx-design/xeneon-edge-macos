# xeneonctl

A tiny command-line tool for controlling screen settings — brightness,
contrast, volume, mute, input — on a CORSAIR XENEON EDGE, without
installing iCUE or any other bloated app.

Runs on **macOS (Apple Silicon)** and **Windows**. It should also work
with any other DDC/CI-capable external display, since it just speaks
standard DDC/CI (VESA MCCS) to whatever panel it finds.

## Download a release

If you just want the tool and don't want to build anything, grab the
latest build from the [Releases
page](https://github.com/jeremy-lx-design/xeneon-edge-macos/releases).
Each archive has the `xeneonctl` command-line tool and a
double-clickable GUI; the Windows one bundles its own .NET runtime, so
nothing else needs installing.

| Platform | File | |
| --- | --- | --- |
| Windows (x64) | `xeneonctl-setup-x64.exe` | Installer |
| macOS (Apple Silicon) | `xeneonctl-macos-arm64.zip` | Archive |

**Windows.** Run the installer. It installs per-user so there's no admin
prompt, offers to put a shortcut on your desktop, adds a Start Menu
entry, and registers an uninstaller under **Add or remove programs**.
SmartScreen may warn about an unrecognised publisher because the
installer is unsigned — click **More info** → **Run anyway**.

**macOS.** Unzip anywhere and run **Xeneon Edge.app**, or use the
`xeneonctl` binary next to it. These builds are signed ad-hoc but not
notarised, so macOS quarantines them after download. Clear it once:

```sh
xattr -dr com.apple.quarantine ~/Downloads/xeneonctl-macos-arm64
```

Or right-click **Xeneon Edge.app** → **Open** → **Open** to approve it
through Gatekeeper.

Releases are built by [GitHub Actions](.github/workflows/release.yml) on
every `v*` tag.

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

## Build from source

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

To package the same thing the releases ship into `dist/` — a `.app`
bundle on macOS, an installer on Windows:

```sh
make dist
```

Building the Windows installer additionally needs [Inno
Setup](https://jrsoftware.org/isinfo.php) on `PATH` (`choco install
innosetup`). The app icon is committed as `gui-windows/XeneonUI.ico`;
`make icon` regenerates it from `gui-windows/icon.svg` and needs
`rsvg-convert` and ImageMagick.

## Stuck-touch-after-sleep fix (macOS only)

The Xeneon Edge has a known quirk where its touchscreen can get "stuck"
in a pressed state after your Mac wakes from sleep, blocking clicks until
you tap the panel once. There's an optional background helper that
automates that tap on every wake — see [`wakefix/`](wakefix/README.md).

This works around an Apple-specific sleep/wake behaviour and has no
Windows equivalent; `make wakefix` is a no-op there.
