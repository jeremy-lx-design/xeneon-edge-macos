// xeneon-wakefix - a tiny background helper that works around a known
// Xeneon Edge quirk: its touchscreen enumerates as a plain USB HID mouse,
// and if the last report before system sleep was a "button down" with no
// matching "up" (e.g. a finger near the panel when the Mac slept), macOS
// wakes up believing the mouse button is still held - blocking clicks
// everywhere until you tap the panel once to send a fresh "up" report.
//
// This just automates that tap: on wake, it posts a synthetic left-mouse-up
// event at the current cursor position, which clears the stuck state the
// same way a real touch would.
import AppKit
import CoreGraphics

let wakeDelaySeconds: TimeInterval = 1.5

func requestAccessibilityPermissionIfNeeded() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
}

func releaseStuckMouseButton() {
    guard let probe = CGEvent(source: nil) else { return }
    let location = probe.location
    guard let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left) else { return }
    mouseUp.post(tap: .cghidEventTap)
}

final class WakeObserver {
    private var lastFired = Date.distantPast

    init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func handleWake() {
        // Both notifications can fire for the same physical wake; collapse duplicates.
        let now = Date()
        guard now.timeIntervalSince(lastFired) > 5 else { return }
        lastFired = now

        DispatchQueue.main.asyncAfter(deadline: .now() + wakeDelaySeconds) {
            releaseStuckMouseButton()
        }
    }
}

requestAccessibilityPermissionIfNeeded()
let observer = WakeObserver()
RunLoop.main.run()
