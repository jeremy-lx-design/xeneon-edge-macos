# xeneon-wakefix

A tiny background helper that works around a known Xeneon Edge quirk: on
macOS its touchscreen enumerates as a plain USB HID mouse, and if the last
report before system sleep was a "button down" with no matching "up" (e.g.
a finger near the panel when the Mac slept), macOS wakes up believing the
mouse button is still held down - blocking clicks everywhere until you tap
the panel once to send a fresh "up" report.

This automates that tap: on wake, it posts a synthetic left-mouse-up event
at the current cursor position, which clears the stuck state the same way
a real touch would. It doesn't touch the display's settings or the
`xeneonctl` CLI/GUI at all - it's a separate, optional fix for this one
specific annoyance.

## Install

```sh
sudo make install-wakefix
```

This builds the helper, installs it to `/usr/local/bin/xeneon-wakefix`, and
registers it as a per-user LaunchAgent so it starts at login and keeps
running in the background.

The first time it runs, macOS will prompt you to grant it **Accessibility**
access (System Settings > Privacy & Security > Accessibility) - it needs
this to post the synthetic mouse-up event. Approve it once and you're done.

## Uninstall

```sh
make uninstall-wakefix
```

## Notes

- This is a workaround for a symptom, not a real fix for the touch
  controller - it just automates the "tap the screen once" trick.
- It only posts a mouse-*up* event, never a down, so it can't accidentally
  trigger a click - at worst it's a harmless no-op if nothing was stuck.
