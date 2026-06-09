import SwiftUI

struct SelectionOverlayView: View {
    let screenFrame: NSRect
    let frozenImage: CGImage?      // visible frozen background (freeze pref)
    var sampleImage: CGImage?      // clean source the loupe samples for true colors
    let onCapture: (CGRect) -> Void
    let onCancel: () -> Void
    var dimOverlay: Bool = true   // false = Shottr "no-overlay" mode (transparent background)
    var showMagnifier: Bool = true

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var isDragging = false
    @State private var hovering = false
    @State private var mouseLocation: CGPoint = .zero
    @State private var hexColor: String?

    private var selectionRect: CGRect? {
        guard let s = dragStart, let c = dragCurrent else { return nil }
        return CGRect(
            x: min(s.x, c.x), y: min(s.y, c.y),
            width: abs(c.x - s.x), height: abs(c.y - s.y)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Invisible base layer — guarantees the ZStack is always hit-testable,
                // even in no-dim mode where all other layers are transparent.
                Color.white.opacity(0.001)
                dimmingOverlay
                crosshairGuides
                selectionOverlay
                magnifierOverlay
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    mouseLocation = p
                    hovering = true
                case .ended:
                    hovering = false
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }

    // Shottr-correct dimming: the SELECTION is always crisp. We only ever dim the
    // surroundings. "dim off" keeps the screen fully visible and lets the bright
    // border do the work; "dim on" darkens everything outside the selection.
    @ViewBuilder
    private var dimmingOverlay: some View {
        let fullSize = CGSize(width: screenFrame.width, height: screenFrame.height)

        if let img = frozenImage {
            Image(img, scale: 1, label: Text(""))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: screenFrame.width, height: screenFrame.height)
                .allowsHitTesting(false)
        }

        if let rect = selectionRect, isDragging {
            // During drag: dim everything except the selection (even-odd cut-out).
            Path { p in
                p.addRect(CGRect(origin: .zero, size: fullSize))
                p.addRect(rect)
            }
            .fill(Color.black.opacity(dimOverlay ? 0.45 : 0.12), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
        } else if dimOverlay {
            // Pre-drag, dim-on: a soft veil so the cursor/loupe read clearly.
            Color.black.opacity(0.28)
                .allowsHitTesting(false)
        }
    }

    // Full-screen alignment guides that track the cursor (Shottr-style).
    @ViewBuilder
    private var crosshairGuides: some View {
        if (hovering || isDragging) {
            CrosshairGuides(at: mouseLocation,
                            size: CGSize(width: screenFrame.width, height: screenFrame.height))
        }
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if let rect = selectionRect, isDragging {
            SelectionRectBorder(rect: rect)
            DimensionLabel(
                size: CGSize(width: rect.width, height: rect.height),
                rect: rect,
                bounds: CGSize(width: screenFrame.width, height: screenFrame.height)
            )
        }
    }

    @ViewBuilder
    private var magnifierOverlay: some View {
        if showMagnifier && (hovering || isDragging) {
            let block = magnifierPlacement()
            VStack(spacing: 6) {
                MagnifierView(
                    viewPoint: mouseLocation,
                    screenFrame: screenFrame,
                    frozenImage: sampleImage,
                    hexColor: $hexColor
                )
                .frame(width: 118, height: 118)

                MagnifierHUD(
                    hex: hexColor,
                    point: mouseLocation,
                    selection: selectionRect
                )
            }
            .position(x: block.x, y: block.y)
            .allowsHitTesting(false)
        }
    }

    /// Keeps the loupe + HUD fully on-screen, preferring the upper-right of the
    /// cursor and flipping near the right/top edges.
    private func magnifierPlacement() -> CGPoint {
        let blockW: CGFloat = 130
        let blockH: CGFloat = 170
        let gap: CGFloat = 26
        var cx = mouseLocation.x + gap + blockW / 2
        if cx + blockW / 2 > screenFrame.width { cx = mouseLocation.x - gap - blockW / 2 }
        var cy = mouseLocation.y - gap - blockH / 2
        if cy - blockH / 2 < 0 { cy = mouseLocation.y + gap + blockH / 2 }
        cx = min(max(cx, blockW / 2 + 4), screenFrame.width - blockW / 2 - 4)
        cy = min(max(cy, blockH / 2 + 4), screenFrame.height - blockH / 2 - 4)
        return CGPoint(x: cx, y: cy)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    dragStart = value.startLocation
                    isDragging = true
                }
                dragCurrent = value.location
                mouseLocation = value.location
            }
            .onEnded { value in
                guard let start = dragStart else { return }
                let end = value.location
                let rect = CGRect(
                    x: min(start.x, end.x), y: min(start.y, end.y),
                    width: abs(end.x - start.x), height: abs(end.y - start.y)
                )
                if rect.width > 3 && rect.height > 3 {
                    onCapture(rect)
                } else {
                    onCancel()
                }
            }
    }
}

/// Thin full-screen crosshair lines that follow the cursor. Double-stroked so
/// they stay visible over any background. Two lines → negligible cost.
struct CrosshairGuides: View {
    let at: CGPoint
    let size: CGSize

    var body: some View {
        Canvas { ctx, _ in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: at.y));        path.addLine(to: CGPoint(x: size.width, y: at.y))
            path.move(to: CGPoint(x: at.x, y: 0));        path.addLine(to: CGPoint(x: at.x, y: size.height))
            ctx.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5))
            ctx.stroke(path, with: .color(.white.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
        }
        .allowsHitTesting(false)
    }
}

/// Readout under the loupe: hex color of the target pixel, cursor coordinates,
/// and the live selection size when dragging.
struct MagnifierHUD: View {
    let hex: String?
    let point: CGPoint
    let selection: CGRect?

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(swatchColor)
                    .frame(width: 10, height: 10)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.6), lineWidth: 0.5))
                Text(hex ?? "#------")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            if let s = selection {
                Text("\(Int(s.width)) × \(Int(s.height))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            } else {
                Text("\(Int(point.x)), \(Int(point.y))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var swatchColor: Color {
        guard let h = hex, h.hasPrefix("#"), h.count == 7,
              let v = Int(h.dropFirst(), radix: 16) else { return .gray }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

struct SelectionRectBorder: View {
    let rect: CGRect

    var body: some View {
        Canvas { ctx, _ in
            // Double-stroked border: dark outline → white fill.
            // Readable on any background (bright or dark screen content).
            let border = Path(rect)
            ctx.stroke(border, with: .color(.black.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 3))
            ctx.stroke(border, with: .color(.white),
                       style: StrokeStyle(lineWidth: 1.5))

            // L-shaped corner brackets — same double-stroke treatment
            let arm:  CGFloat = 16
            let corners: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: rect.minX, y: rect.minY),  arm,  arm),   // ↘
                (CGPoint(x: rect.maxX, y: rect.minY), -arm,  arm),   // ↙
                (CGPoint(x: rect.minX, y: rect.maxY),  arm, -arm),   // ↗
                (CGPoint(x: rect.maxX, y: rect.maxY), -arm, -arm),   // ↖
            ]
            for (p, dx, dy) in corners {
                var bracket = Path()
                bracket.move(to: CGPoint(x: p.x + dx, y: p.y))
                bracket.addLine(to: p)
                bracket.addLine(to: CGPoint(x: p.x, y: p.y + dy))
                ctx.stroke(bracket, with: .color(.black.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 4.5, lineCap: .square))
                ctx.stroke(bracket, with: .color(.white),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .square))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Size badge pinned to the selection's top-left. Sits just above the selection,
/// flips inside when the selection hugs the top edge, and clamps within the
/// screen so it can never be cut off.
struct DimensionLabel: View {
    let size: CGSize
    let rect: CGRect
    let bounds: CGSize

    private let estWidth: CGFloat = 92
    private let badgeHeight: CGFloat = 20

    var body: some View {
        Text("\(Int(size.width)) × \(Int(size.height))")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .position(badgePosition)
            .allowsHitTesting(false)
    }

    private var badgePosition: CGPoint {
        // Prefer just above the top edge; flip below the top edge if no room.
        let above = rect.minY - badgeHeight / 2 - 4
        let y = above < 8 ? rect.minY + badgeHeight / 2 + 4 : above
        var x = rect.minX + estWidth / 2
        x = min(max(x, estWidth / 2 + 2), bounds.width - estWidth / 2 - 2)
        return CGPoint(x: x, y: y)
    }
}
