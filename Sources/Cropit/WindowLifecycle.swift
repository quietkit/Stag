import Cocoa

/// Shottr-style activation policy management.
///
/// The app launches as `.accessory` (no Dock icon, no Cmd+Tab entry).
/// When any "main" window (Editor, Settings, History) opens, it switches to
/// `.regular` so the app appears in the Dock and Mission Control.
/// When the last main window closes it reverts to `.accessory`.
///
/// Usage — in every main window:
///   - `show()`:              call `WindowLifecycle.didOpen(self)`
///   - `windowWillClose`:     call `WindowLifecycle.didClose(self)`
enum WindowLifecycle {

    /// Call when a main window is about to appear.
    @MainActor
    static func didOpen(_ window: NSWindow) {
        openWindows.insert(ObjectIdentifier(window))
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Call from `windowWillClose` (NSWindowDelegate).
    @MainActor
    static func didClose(_ window: NSWindow) {
        openWindows.remove(ObjectIdentifier(window))
        if openWindows.isEmpty {
            // Small delay prevents flicker when one window closes and another
            // is about to open (e.g. "Settings → open Editor").
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if openWindows.isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    // MARK: - Private

    private static var openWindows = Set<ObjectIdentifier>()
}
