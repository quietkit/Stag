import Cocoa

// MARK: - Shared Selection Helper

enum RecordingTargetSelector {
    /// Region selector for screen recording / GIF. Uses the SAME rich selection
    /// overlay as area capture (adjustable handles, action bar, loupe, crosshair,
    /// window hover-highlight) but returns the selected screen rect instead of an
    /// image.
    static func select(mode: CaptureMode = .recording) async throws -> (CGRect, CGDirectDisplayID) {
        let prefs = AppStore.shared.preferences
        let freeze = prefs.freezeScreenBeforeCapture
        let showMagnifier = prefs.showMagnifier
        let dimOverlay = prefs.dimSelectionOverlay
        let showCrosshair = prefs.showCrosshair
        let directCapture = prefs.directCapture

        let composite = (freeze || showMagnifier) ? (try? await ScreenComposite.capture()) : nil

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let overlay = SelectionOverlayWindow(
                    frozenImage: freeze ? composite : nil,
                    sampleImage: composite,
                    dimOverlay: dimOverlay,
                    showMagnifier: showMagnifier,
                    showCrosshair: showCrosshair,
                    directCapture: directCapture,
                    mode: mode
                )
                overlay.onRectSelected = { rect, displayID in
                    continuation.resume(returning: (rect, displayID))
                }
                overlay.onCancel = {
                    continuation.resume(throwing: CaptureError.noActiveCapture)
                }
                overlay.show()
            }
        }
    }
}

// MARK: - Recording Rect Overlay

final class RecordingRectOverlay: NSWindow {
    var onRectSelected: ((CGRect, CGDirectDisplayID) -> Void)?
    var onCancel: (() -> Void)?

    init() {
        let totalFrame = NSScreen.screens.reduce(NSZeroRect) { $0.union($1.frame) }
        super.init(
            contentRect: totalFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.15)
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = RecordingRectView()
        view.frame = NSRect(origin: .zero, size: totalFrame.size)
        view.autoresizingMask = [.width, .height]
        view.onRectSelected = { [weak self] rect in
            guard let self = self else { return }
            // rect is in view coords (flipped: y=0 at top, y increases downward).
            // Convert to absolute screen coords (Cocoa: y=0 at bottom).
            let cvHeight = self.contentView?.frame.height ?? totalFrame.height
            let screenRect = NSRect(
                x: rect.minX + self.frame.origin.x,
                y: self.frame.origin.y + cvHeight - rect.maxY,   // flip y → Cocoa screen coords
                width: rect.width,
                height: rect.height
            )
            let screen = NSScreen.screens.first(where: { $0.frame.intersects(screenRect) })
            let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
                ?? CGMainDisplayID()
            NSCursor.crosshair.pop()
            self.onRectSelected?(screenRect, displayID)
            self.close()
        }
        view.onCancel = { [weak self] in
            self?.onCancel?()
            self?.close()
        }
        contentView = view
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
    }

    override func cancelOperation(_ sender: Any?) {
        NSCursor.crosshair.pop()
        onCancel?()
        close()
    }
}

// MARK: - Recording Rect View

final class RecordingRectView: NSView {
    var onRectSelected: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var isDragging = false

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        let rect = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
        if rect.width > 10 && rect.height > 10 {
            onRectSelected?(rect)
        } else {
            onCancel?()
        }
        isDragging = false
        dragStart = nil
        dragCurrent = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.2))
        ctx.fill(dirtyRect)

        guard isDragging, let start = dragStart, let current = dragCurrent else { return }
        let rect = CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
        ctx.clear(rect)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
        ctx.setLineWidth(2)
        ctx.stroke(rect)

        // Dimension label
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        (label as NSString).draw(at: NSPoint(x: rect.maxX + 6, y: rect.minY), withAttributes: attrs)
    }
}
