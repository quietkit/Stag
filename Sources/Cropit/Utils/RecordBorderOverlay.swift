import Cocoa

/// Thin border window that sticks around the recorded area while recording/GIF is active.
final class RecordBorderOverlay: NSWindow {
    fileprivate static let borderWidth: CGFloat = 3

    init(rect: CGRect) {
        // Expand slightly so the border isn't clipped inside the recorded area.
        let margin: CGFloat = 1
        let outerRect = rect.insetBy(dx: -margin, dy: -margin)
        super.init(
            contentRect: outerRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver + 1
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let borderView = BorderView(frame: NSRect(origin: .zero, size: outerRect.size))
        borderView.autoresizingMask = [.width, .height]
        contentView = borderView
    }

    func show() {
        orderFront(nil)
    }

    override func close() {
        super.close()
    }
}

private final class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setStrokeColor(Palette.borderRed)
        ctx.setLineWidth(RecordBorderOverlay.borderWidth)
        ctx.stroke(bounds.insetBy(dx: RecordBorderOverlay.borderWidth / 2,
                                  dy: RecordBorderOverlay.borderWidth / 2))
    }
}
