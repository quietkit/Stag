import SwiftUI
import AppKit

// MARK: - Model

enum BackdropKind: String, CaseIterable {
    case none, solid, gradient, image

    var displayName: String {
        switch self {
        case .none:     return "None"
        case .solid:    return "Solid"
        case .gradient: return "Gradient"
        case .image:    return "Image"
        }
    }
}

/// "Beautiful screenshot" styling applied around the annotated image — a colored
/// or gradient backdrop with padding, rounded corners, a drop shadow and an
/// optional macOS window frame. Drives both the live preview and the export.
struct BackdropStyle {
    var kind: BackdropKind = .none
    var solidColor: Color = Color(red: 0.95, green: 0.95, blue: 0.97)
    var gradientIndex: Int = 0
    var wallpaper: NSImage? = nil

    /// Padding as a fraction of the screenshot's longest edge (keeps margins
    /// proportional regardless of capture size).
    var paddingFraction: CGFloat = 0.08
    var cornerRadius: CGFloat = 14          // image-space points
    var shadowRadius: CGFloat = 28
    var shadowOpacity: CGFloat = 0.35
    var showWindowFrame: Bool = false

    var isActive: Bool { kind != .none }

    static let gradients: [GradientPreset] = [
        .init(name: "Sunset",  colors: [hex(0xFF7E5F), hex(0xFEB47B)]),
        .init(name: "Bloom",   colors: [hex(0xFF6CAB), hex(0x7366FF)]),
        .init(name: "Ocean",   colors: [hex(0x2193B0), hex(0x6DD5ED)]),
        .init(name: "Mint",    colors: [hex(0x11998E), hex(0x38EF7D)]),
        .init(name: "Grape",   colors: [hex(0x654EA3), hex(0xEAAFC8)]),
        .init(name: "Peach",   colors: [hex(0xFFD194), hex(0xF79D7D)]),
        .init(name: "Sky",     colors: [hex(0x89F7FE), hex(0x66A6FF)]),
        .init(name: "Mono",    colors: [hex(0x232526), hex(0x414345)]),
    ]

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255)
    }
}

struct GradientPreset: Identifiable {
    let id = UUID()
    let name: String
    let colors: [Color]

    var swiftUIGradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Shared geometry

enum BackdropMetrics {
    /// Title-bar height in image-space points, proportional to width and clamped.
    static func barHeight(width: CGFloat) -> CGFloat {
        min(max(width * 0.045, 26), 56)
    }
    /// The card = screenshot plus the optional window-frame bar on top.
    static func cardSize(content: CGSize, style: BackdropStyle) -> CGSize {
        let bar = style.showWindowFrame ? barHeight(width: content.width) : 0
        return CGSize(width: content.width, height: content.height + bar)
    }
    static func padding(content: CGSize, style: BackdropStyle) -> CGFloat {
        style.paddingFraction * max(content.width, content.height)
    }
}

// MARK: - Export compositor (Core Graphics, y-up)

enum Backdrop {
    /// Composites the already-flattened annotated screenshot onto the styled
    /// backdrop. Called once at export — never per frame.
    static func compose(content: NSImage, style: BackdropStyle) -> NSImage {
        let cw = content.size.width, ch = content.size.height
        guard style.isActive, cw > 0, ch > 0 else { return content }

        let pad = BackdropMetrics.padding(content: content.size, style: style)
        let bar = style.showWindowFrame ? BackdropMetrics.barHeight(width: cw) : 0
        let cardW = cw, cardH = ch + bar
        let outW = (cardW + 2 * pad).rounded()
        let outH = (cardH + 2 * pad).rounded()

        let out = NSImage(size: NSSize(width: outW, height: outH))
        out.lockFocus()
        defer { out.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return content }

        drawBackground(ctx, rect: CGRect(x: 0, y: 0, width: outW, height: outH), style: style)

        let cardRect = CGRect(x: pad, y: pad, width: cardW, height: cardH)
        let radius = min(style.cornerRadius, min(cardW, cardH) / 2)
        let cardPath = CGPath(roundedRect: cardRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Drop shadow + opaque card base (so the shadow reads on any background).
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -style.shadowRadius * 0.3),
                      blur: style.shadowRadius,
                      color: NSColor.black.withAlphaComponent(style.shadowOpacity).cgColor)
        ctx.addPath(cardPath)
        ctx.setFillColor(chromeColor.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Clip to the rounded card, draw the screenshot, then the window chrome.
        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.clip()
        content.draw(in: CGRect(x: pad, y: pad, width: cw, height: ch),
                     from: .zero, operation: .sourceOver, fraction: 1)
        if style.showWindowFrame {
            drawTrafficLights(ctx, barRect: CGRect(x: pad, y: pad + ch, width: cw, height: bar))
        }
        ctx.restoreGState()

        return out
    }

    static let chromeColor = NSColor(calibratedWhite: 0.93, alpha: 1)

    private static func drawBackground(_ ctx: CGContext, rect: CGRect, style: BackdropStyle) {
        switch style.kind {
        case .none:
            break
        case .solid:
            ctx.setFillColor(NSColor(style.solidColor).cgColor)
            ctx.fill(rect)
        case .gradient:
            let preset = BackdropStyle.gradients[min(style.gradientIndex, BackdropStyle.gradients.count - 1)]
            let cgColors = preset.colors.map { NSColor($0).cgColor } as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: space, colors: cgColors, locations: [0, 1]) {
                ctx.saveGState()
                ctx.addRect(rect); ctx.clip()
                // top-leading → bottom-trailing
                ctx.drawLinearGradient(grad,
                                       start: CGPoint(x: rect.minX, y: rect.maxY),
                                       end: CGPoint(x: rect.maxX, y: rect.minY),
                                       options: [])
                ctx.restoreGState()
            }
        case .image:
            if let wp = style.wallpaper {
                // aspect-fill the output rect
                let s = max(rect.width / wp.size.width, rect.height / wp.size.height)
                let dw = wp.size.width * s, dh = wp.size.height * s
                let dr = CGRect(x: rect.midX - dw / 2, y: rect.midY - dh / 2, width: dw, height: dh)
                wp.draw(in: dr, from: .zero, operation: .copy, fraction: 1)
            } else {
                ctx.setFillColor(NSColor(style.solidColor).cgColor)
                ctx.fill(rect)
            }
        }
    }

    private static func drawTrafficLights(_ ctx: CGContext, barRect: CGRect) {
        let d = min(max(barRect.height * 0.30, 8), 16)
        let cy = barRect.midY
        let colors = [NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 1),
                      NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.18, alpha: 1),
                      NSColor(calibratedRed: 0.16, green: 0.80, blue: 0.27, alpha: 1)]
        for (i, c) in colors.enumerated() {
            let x = barRect.minX + d * 1.4 + CGFloat(i) * d * 1.7
            ctx.setFillColor(c.cgColor)
            ctx.fillEllipse(in: CGRect(x: x, y: cy - d / 2, width: d, height: d))
        }
    }
}

// MARK: - Live preview background (SwiftUI, cheap — no per-frame bitmap compositing)

struct BackdropBackground: View {
    let style: BackdropStyle

    var body: some View {
        switch style.kind {
        case .none:
            Color.clear
        case .solid:
            style.solidColor
        case .gradient:
            BackdropStyle.gradients[min(style.gradientIndex, BackdropStyle.gradients.count - 1)]
                .swiftUIGradient
        case .image:
            if let wp = style.wallpaper {
                Image(nsImage: wp).resizable().aspectRatio(contentMode: .fill)
            } else {
                style.solidColor
            }
        }
    }
}

/// macOS-style title bar with traffic lights, drawn above the screenshot in the
/// live preview. Sized in view points so it matches the export compositor.
struct WindowChromeBar: View {
    let height: CGFloat

    var body: some View {
        HStack(spacing: height * 0.34) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34))
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18))
            Circle().fill(Color(red: 0.16, green: 0.80, blue: 0.27))
            Spacer(minLength: 0)
        }
        .frame(width: max(height * 2.6, 1), height: height * 0.30)
        .padding(.leading, height * 0.55)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(Color(nsColor: Backdrop.chromeColor))
    }
}
