import SwiftUI
import AppKit

/// Shottr-style pixel loupe.
///
/// Performance: when a `frozenImage` (the pre-captured screen composite) is
/// available, the loupe samples directly from that in-memory bitmap — no
/// per-frame screen capture at all. When there is no frozen image it falls back
/// to a small synchronous grab, but only when the cursor actually moves to a new
/// pixel (deduped), so we never re-read the same region twice.
struct MagnifierView: NSViewRepresentable {
    let viewPoint: CGPoint        // cursor location in overlay-view coords (y-down)
    let screenFrame: NSRect       // total multi-display frame (Cocoa, y-up)
    let frozenImage: CGImage?     // optional in-memory sampling source
    @Binding var hexColor: String?

    func makeNSView(context: Context) -> MagnifierHostView {
        let v = MagnifierHostView()
        v.onHex = { hex in
            // Report back on the main queue, deduped, to avoid SwiftUI re-entrancy.
            if hexColor != hex { DispatchQueue.main.async { self.hexColor = hex } }
        }
        return v
    }

    func updateNSView(_ nsView: MagnifierHostView, context: Context) {
        nsView.frozenImage = frozenImage
        nsView.screenFrame = screenFrame
        nsView.update(viewPoint: viewPoint)
    }
}

final class MagnifierHostView: NSView {
    var frozenImage: CGImage?
    var screenFrame: NSRect = .zero
    var onHex: ((String) -> Void)?

    private let zoom: CGFloat = 8          // on-screen px per source px
    private let radius: CGFloat = 55       // loupe radius
    private let captureRadius: Int = 8     // source px sampled around cursor (→ 16px field)

    private var lastPixel: (Int, Int) = (.min, .min)
    private var cachedSample: CGImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Update for a new cursor position. Only triggers a redraw when the integer
    /// source pixel under the cursor actually changes.
    func update(viewPoint: CGPoint) {
        let scale = sampleScale()
        let px = Int((viewPoint.x * scale).rounded(.down))
        let py = Int((viewPoint.y * scale).rounded(.down))
        guard (px, py) != lastPixel else { return }
        lastPixel = (px, py)
        cachedSample = sample(atPixelX: px, pixelY: py)
        if let s = cachedSample { onHex?(Self.centerHex(of: s)) }
        needsDisplay = true
    }

    /// Source-pixels-per-view-point. Frozen image may be Retina (scale ≈ 2);
    /// live fallback samples at 1 source px per point.
    private func sampleScale() -> CGFloat {
        if let f = frozenImage, screenFrame.width > 0 {
            return CGFloat(f.width) / screenFrame.width
        }
        return 1
    }

    private func sample(atPixelX px: Int, pixelY py: Int) -> CGImage? {
        if let frozen = frozenImage {
            // Frozen path — crop in image space (origin top-left). Scale the sample
            // radius by the image's pixel density so the loupe field-of-view matches
            // the live path (captureRadius points on each side) on Retina displays.
            let rPx = max(1, Int((CGFloat(captureRadius) * sampleScale()).rounded()))
            let side = rPx * 2
            let crop = CGRect(x: px - rPx, y: py - rPx, width: side, height: side)
                .intersection(CGRect(x: 0, y: 0, width: frozen.width, height: frozen.height))
            guard !crop.isNull, crop.width > 0 else { return nil }
            return frozen.cropping(to: crop)
        }
        let r = captureRadius
        // Live fallback — convert view point back to a Cocoa screen point.
        let viewX = CGFloat(px), viewY = CGFloat(py)
        let screenX = screenFrame.minX + viewX
        let screenY = screenFrame.minY + (screenFrame.height - viewY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: screenX, y: screenY)) })
        else { return nil }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? CGMainDisplayID()
        let b = CGDisplayBounds(displayID)
        let xLocal = screenX - b.origin.x
        let yLocal = (b.origin.y + b.height) - screenY
        let rect = CGRect(x: xLocal - CGFloat(r), y: yLocal - CGFloat(r), width: CGFloat(r) * 2, height: CGFloat(r) * 2)
        return CGDisplayCreateImage(displayID, rect: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let magRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let circle = CGPath(ellipseIn: magRect, transform: nil)

        ctx.saveGState()
        ctx.addPath(circle)
        ctx.clip()

        if let cap = cachedSample {
            ctx.interpolationQuality = .none
            ctx.draw(cap, in: magRect)
            drawPixelGrid(ctx: ctx, magRect: magRect, sourceSide: cap.width)
        } else {
            ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.85))
            ctx.addPath(circle); ctx.fillPath()
        }

        // Center pixel highlight — a 1-source-pixel square box at the exact target.
        let pxSize = (radius * 2) / CGFloat(max(1, captureRadius * 2))
        let box = CGRect(x: center.x - pxSize / 2, y: center.y - pxSize / 2, width: pxSize, height: pxSize)
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.9))
        ctx.setLineWidth(2); ctx.stroke(box)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.setLineWidth(1); ctx.stroke(box)
        ctx.restoreGState()

        // Loupe rim — double stroked for contrast on any background.
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        ctx.setLineWidth(3); ctx.addPath(circle); ctx.strokePath()
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.setLineWidth(1.5); ctx.addPath(circle); ctx.strokePath()
    }

    private func drawPixelGrid(ctx: CGContext, magRect: CGRect, sourceSide: Int) {
        guard sourceSide > 0 else { return }
        let step = magRect.width / CGFloat(sourceSide)
        guard step >= 4 else { return }   // skip grid when too dense to be useful
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.12))
        ctx.setLineWidth(0.5)
        var x = magRect.minX
        while x <= magRect.maxX { ctx.move(to: CGPoint(x: x, y: magRect.minY)); ctx.addLine(to: CGPoint(x: x, y: magRect.maxY)); x += step }
        var y = magRect.minY
        while y <= magRect.maxY { ctx.move(to: CGPoint(x: magRect.minX, y: y)); ctx.addLine(to: CGPoint(x: magRect.maxX, y: y)); y += step }
        ctx.strokePath()
    }

    /// Reads the center pixel of a sampled region and returns "#RRGGBB".
    static func centerHex(of image: CGImage) -> String {
        let cx = image.width / 2, cy = image.height / 2
        guard let sub = image.cropping(to: CGRect(x: cx, y: cy, width: 1, height: 1)) else { return "#------" }
        var px: [UInt8] = [0, 0, 0, 0]
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let c = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "#------" }
        c.draw(sub, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return String(format: "#%02X%02X%02X", px[0], px[1], px[2])
    }
}
