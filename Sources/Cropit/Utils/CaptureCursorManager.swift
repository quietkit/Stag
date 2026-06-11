import Cocoa

/// Manages the custom capture‑area cursor for the entire capture session.
/// It ensures the cursor is shown even when the dim overlay is hidden or the user
/// switches to another app and returns.
final class CaptureCursorManager {
    static let shared = CaptureCursorManager()
    private var isActive = false
    private var cursor: NSCursor?
    private var activationObserver: Any?

    private init() {
        // Listen for app activation to re‑apply the cursor if needed.
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.appDidActivate()
        }
    }

    deinit {
        if let obs = activationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// The currently active cursor (read‑only for cursor‑rect registration).
    var currentCursor: NSCursor? { cursor }

    /// Install the custom cursor globally for the capture session.
    func apply() {
        guard !isActive else { return }
        isActive = true
        cursor = CaptureCursorManager.createCursor()
        cursor?.set()
        NSCursor.setHiddenUntilMouseMoves(false)
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
        // Small (18 × 18 pt) circle with a plus sign, double‑stroked for contrast.
        let size: CGFloat = 20
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cx = rect.midX, cy = rect.midY
            let radius: CGFloat = 5.5
            let crossLen: CGFloat = 8

            // Thin double‑stroke for subtle contrast.
            for (lw, color) in [
                (CGFloat(1.2), Palette.cursorDark),
                (CGFloat(0.6), Palette.cursorLight),
            ] {
                ctx.setStrokeColor(color)
                ctx.setLineWidth(lw)

                // Circle
                ctx.addEllipse(in: CGRect(x: cx - radius, y: cy - radius,
                                          width: radius * 2, height: radius * 2))
                ctx.strokePath()

                // Plus sign arms
                ctx.setLineCap(.round)
                ctx.beginPath()
                // Horizontal
                ctx.move(to: CGPoint(x: cx - crossLen, y: cy))
                ctx.addLine(to: CGPoint(x: cx + crossLen, y: cy))
                // Vertical
                ctx.move(to: CGPoint(x: cx, y: cy - crossLen))
                ctx.addLine(to: CGPoint(x: cx, y: cy + crossLen))
                ctx.strokePath()
            }
            return true
        }
        img.isTemplate = false
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }
}
