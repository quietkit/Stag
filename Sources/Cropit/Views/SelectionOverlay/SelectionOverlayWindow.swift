import Cocoa
import SwiftUI
import ScreenCaptureKit

// MARK: - Crosshair hosting view
// Overrides resetCursorRects so AppKit keeps the precision cursor on every
// mouseMoved event — no need to manually re-call NSCursor.set().
private final class CrosshairHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: SelectionOverlayWindow.precisionCursor)
    }
}

// MARK: - Window

final class SelectionOverlayWindow: NSWindow {
    var onCapture: ((CGImage) -> Void)?
    var onCancel:  (() -> Void)?
    /// When set, the overlay returns the selected screen rect + display instead of
    /// capturing an image (used for screen recording / GIF region selection).
    var onRectSelected: ((CGRect, CGDirectDisplayID) -> Void)?
    private let frozenImage: CGImage?      // visible frozen background (freeze pref)

    // MARK: Precision cursor — scope + crosshair, double-stroked for any background
    static let precisionCursor: NSCursor = {
        let size: CGFloat = 44
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cx = rect.midX, cy = rect.midY
            let circleR: CGFloat  = 11
            let gap:     CGFloat  = circleR + 4   // space between circle and arm start
            let armLen:  CGFloat  = 9

            ctx.setLineCap(.butt)

            // Draw twice: thick dark outline → thin white fill  (readable on any bg)
            for (lw, r, g, b, a) in [
                (CGFloat(3.5), CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0.65)),
                (CGFloat(1.8), CGFloat(1), CGFloat(1), CGFloat(1), CGFloat(1.0 )),
            ] {
                ctx.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: a))
                ctx.setLineWidth(lw)

                // Scope circle
                ctx.beginPath()
                ctx.addEllipse(in: CGRect(x: cx - circleR, y: cy - circleR,
                                          width: circleR * 2, height: circleR * 2))
                ctx.strokePath()

                // Four crosshair arms radiating outward from the circle
                let arms: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (cx, cy + gap, cx,        cy + gap + armLen),  // up
                    (cx, cy - gap, cx,        cy - gap - armLen),  // down
                    (cx + gap, cy, cx + gap + armLen, cy        ),  // right
                    (cx - gap, cy, cx - gap - armLen, cy        ),  // left
                ]
                for (x1, y1, x2, y2) in arms {
                    ctx.beginPath()
                    ctx.move(to:    CGPoint(x: x1, y: y1))
                    ctx.addLine(to: CGPoint(x: x2, y: y2))
                    ctx.strokePath()
                }
            }

            // Centre dot
            let dotR: CGFloat = 1.8
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR*2, height: dotR*2))

            return true
        }
        img.isTemplate = false   // keep white/black colours; don't let system tint it
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }()

    // MARK: Init

    /// - Parameters:
    ///   - frozenImage: shown as a frozen background (only when the freeze pref is on).
    ///   - sampleImage: clean composite the loupe samples from (independent of the
    ///     visible background) so pixel colors read true, not through our dim overlay.
    init(frozenImage: CGImage? = nil, sampleImage: CGImage? = nil,
         dimOverlay: Bool = true, showMagnifier: Bool = true, showCrosshair: Bool = true,
         windows: [DetectedWindow] = []) {
        self.frozenImage = frozenImage
        let screens = NSScreen.screens
        let totalFrame = screens.reduce(NSZeroRect) { $0.union($1.frame) }

        // Convert window frames (CG global, top-left origin, y-down) into the
        // overlay's SwiftUI view space (origin at the overlay's top-left, y-down).
        let primaryHeight = screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? (NSScreen.main?.frame.height ?? totalFrame.height)
        let windowHits: [WindowHit] = windows.map { w in
            WindowHit(
                rect: WindowFrameMapper.viewRect(cgFrame: w.frame,
                                                 totalFrame: totalFrame,
                                                 primaryHeight: primaryHeight),
                title: w.title
            )
        }

        super.init(
            contentRect: totalFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = SelectionOverlayView(
            screenFrame: totalFrame,
            frozenImage: frozenImage,
            sampleImage: sampleImage ?? frozenImage,
            onCapture: { [weak self] rect in Task { await self?.performCapture(rect) } },
            onCancel:  { [weak self] in
                Self.precisionCursor.pop()
                self?.onCancel?()
                self?.close()
            },
            dimOverlay: dimOverlay,
            showMagnifier: showMagnifier,
            showCrosshair: showCrosshair,
            detectedWindows: windowHits
        )

        // Use CrosshairHostingView so cursor rects are auto-managed by AppKit
        let hosting = CrosshairHostingView(rootView: overlayView)
        hosting.frame = NSRect(origin: .zero, size: totalFrame.size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    // MARK: Show / hide

    func show() {
        CaptureCursorManager.shared.apply()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Force it visible immediately — without this the cursor only updates on the
        // first mouse-move, so it looks unchanged until you start dragging.
        CaptureCursorManager.shared.cursor?.set()
        DispatchQueue.main.async { [weak self] in
            guard let self, let cv = self.contentView else { return }
            self.invalidateCursorRects(for: cv)
        }
    }

    // MARK: Capture

    private func performCapture(_ viewRect: CGRect) async {
        guard let contentView = self.contentView else { return }
        let cvHeight      = contentView.frame.height
        let windowOriginX = frame.origin.x
        let windowOriginY = frame.origin.y

        Self.precisionCursor.pop()
        close()

        // Convert SwiftUI view coords (y=0 top) → Cocoa screen coords (y=0 bottom)
        let cgX    = viewRect.minX + windowOriginX
        let cgMinY = windowOriginY + cvHeight - viewRect.maxY   // bottom of selection
        let cgMaxY = cgMinY + viewRect.height                   // top of selection

        let selectionOrigin = CGPoint(x: cgX, y: cgMinY)
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.intersects(NSRect(origin: selectionOrigin,
                                       size: CGSize(width: viewRect.width, height: viewRect.height)))
        }) else { return }

        let displayFrame = screen.frame
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            ?? CGMainDisplayID()

        // ── Rect-only mode: hand back the selected screen rect (for recording/GIF)
        //    instead of capturing an image. ────────────────────────────────────
        if let onRectSelected {
            let screenRect = CGRect(x: cgX, y: cgMinY, width: viewRect.width, height: viewRect.height)
            onRectSelected(screenRect, displayID)
            return
        }

        // ── Frozen-image path: crop the pre-captured composite ──────────────
        if let frozen = frozenImage {
            let totalFrame = NSScreen.screens.reduce(NSZeroRect) { $0.union($1.frame) }
            guard totalFrame.width > 0, totalFrame.height > 0 else { return }
            let sx = CGFloat(frozen.width)  / totalFrame.width
            let sy = CGFloat(frozen.height) / totalFrame.height
            // CGImage.cropping uses y=0 at BOTTOM
            let cropRect = CGRect(
                x: (cgX    - totalFrame.origin.x) * sx,
                y: (cgMinY - totalFrame.origin.y) * sy,
                width:  viewRect.width  * sx,
                height: viewRect.height * sy
            )
            if let cropped = frozen.cropping(to: cropRect) { onCapture?(cropped) }
            return
        }

        // ── Live capture: use SCStreamConfiguration.sourceRect ───────────────
        // This tells SCKit to capture ONLY the selected region — no post-crop math.
        // sourceRect is display-relative with y=0 at TOP of display.
        let scale     = screen.backingScaleFactor
        let srcX      = cgX - displayFrame.origin.x
        let srcY      = displayFrame.maxY - cgMaxY  // flip Cocoa → top-origin

        do {
            let content   = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID })
            else { return }

            let ourBundleID = Bundle.main.bundleIdentifier ?? ""
            let ourWindows  = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == ourBundleID
            }
            let filter = SCContentFilter(display: scDisplay, excludingWindows: ourWindows)

            let config = SCStreamConfiguration()
            config.pixelFormat    = kCVPixelFormatType_32BGRA
            config.showsCursor    = false
            config.sourceRect     = CGRect(x: srcX, y: srcY,
                                           width: viewRect.width, height: viewRect.height)
            config.width          = max(1, Int(viewRect.width  * scale))
            config.height         = max(1, Int(viewRect.height * scale))

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            onCapture?(image)
        } catch {}
    }

    // MARK: ESC / key

    override func cancelOperation(_ sender: Any?) {
        Self.precisionCursor.pop()
        onCancel?()
        close()
    }

    override var canBecomeKey:        Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
