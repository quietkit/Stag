import Cocoa

/// Manages the custom capture‑area cursor for the entire capture session.
/// It ensures the cursor is shown even when the dim overlay is hidden or the user
/// switches to another app and returns.
final class CaptureCursorManager {
    static let shared = CaptureCursorManager()
    private var isActive = false
    private var cursor: NSCursor?

    private init() {
        // Listen for app activation to re‑apply the cursor if needed.
        NotificationCenter.default.addObserver(self, selector: #selector(appDidActivate), name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    /// Install the custom cursor globally for the capture session.
    func apply() {
        guard !isActive else { return }
        isActive = true
        cursor = CaptureCursorManager.createCursor()
        cursor?.set()
    }

    /// Remove the custom cursor and restore the system default.
    func remove() {
        guard isActive else { return }
        isActive = false
        cursor?.pop()
        cursor = nil
    }

    @objc private func appDidActivate() {
        // When the app regains focus during a capture, re‑apply the cursor.
        if isActive {
            cursor?.set()
        }
    }

    // MARK: - Cursor creation
    private static func createCursor() -> NSCursor {
        // Small (12 × 12 pt) circle with thin stroke, suitable for Light/Dark mode.
        let size: CGFloat = 12
        let img = NSImage(size: NSSize(width: size, height: size)) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 5
            ctx.setLineWidth(1.0)
            // Use labelColor for contrast on both themes.
            let stroke = NSColor.labelColor.cgColor
            ctx.setStrokeColor(stroke)
            ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ctx.strokePath()
            return true
        }
        img.isTemplate = false
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }
}
