import SwiftUI
import AppKit

struct MagnifierView: NSViewRepresentable {
    let mouseLocation: CGPoint
    let windowOrigin: CGPoint
    let windowHeight: CGFloat

    func makeNSView(context: Context) -> MagnifierHostView {
        MagnifierHostView()
    }

    func updateNSView(_ nsView: MagnifierHostView, context: Context) {
        let screenX = windowOrigin.x + mouseLocation.x
        let screenY = windowOrigin.y + windowHeight - mouseLocation.y
        nsView.captureScreenPoint = CGPoint(x: screenX, y: screenY)
        nsView.needsDisplay = true
    }
}

final class MagnifierHostView: NSView {
    var captureScreenPoint: CGPoint = .zero
    private let zoom: CGFloat = 8
    private let radius: CGFloat = 50
    private let captureRadius: CGFloat = 6

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let capImage = captureZoomedPixels()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let magRect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )

        ctx.saveGState()
        let path = CGPath(ellipseIn: magRect, transform: nil)
        ctx.addPath(path)
        ctx.clip()

        if let cap = capImage {
            ctx.interpolationQuality = .none
            ctx.draw(cap, in: magRect)
        } else {
            ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8))
            ctx.addPath(path)
            ctx.fillPath()
        }

        ctx.resetClip()
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.setLineWidth(2)
        ctx.addPath(path)
        ctx.strokePath()

        ctx.setStrokeColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.7))
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: center.x - 8, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x + 8, y: center.y))
        ctx.move(to: CGPoint(x: center.x, y: center.y - 8))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y + 8))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func captureZoomedPixels() -> CGImage? {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(captureScreenPoint)
        }) else { return nil }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            ?? CGMainDisplayID()
        let displayBounds = CGDisplayBounds(displayID)

        let xLocal = captureScreenPoint.x - displayBounds.origin.x
        let yLocal = (displayBounds.origin.y + displayBounds.height) - captureScreenPoint.y

        let captureRect = CGRect(
            x: xLocal - captureRadius,
            y: yLocal - captureRadius,
            width: captureRadius * 2,
            height: captureRadius * 2
        )

        return CGDisplayCreateImage(displayID, rect: captureRect)
    }
}
