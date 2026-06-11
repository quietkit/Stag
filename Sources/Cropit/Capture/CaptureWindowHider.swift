import Cocoa

/// Hides Cropit's own visible windows (Editor, History, Settings) for the
/// duration of a capture, so they don't appear over — or show through — the
/// selection overlay. Without this, triggering a capture activates the app and
/// brings those windows forward, which is exactly what the user is trying to
/// capture *behind*.
final class CaptureWindowHider {
    static let shared = CaptureWindowHider()
    private init() {}

    private var hidden: [NSWindow] = []

    func hide() {
        // Titled windows are our editor/history/settings; borderless ones are the
        // overlay / HUD / toast, which must stay.
        hidden = NSApp.windows.filter {
            $0.isVisible && $0.styleMask.contains(.titled)
        }
        hidden.forEach { $0.orderOut(nil) }
    }

    func restore() {
        // orderFront before any new post-capture editor opens, so the new window
        // ends up on top of the restored ones.
        hidden.forEach { $0.orderFront(nil) }
        hidden.removeAll()
    }
}
