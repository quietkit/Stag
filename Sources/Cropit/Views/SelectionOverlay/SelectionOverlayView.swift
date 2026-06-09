import SwiftUI

struct SelectionOverlayView: View {
    let screenFrame: NSRect
    let frozenImage: CGImage?
    let onCapture: (CGRect) -> Void
    let onCancel: () -> Void
    var dimOverlay: Bool = true   // false = Shottr "no-overlay" mode (transparent background)
    var showMagnifier: Bool = true

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var isDragging = false
    @State private var mouseLocation: CGPoint = .zero

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
                selectionOverlay
                magnifierOverlay
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .edgesIgnoringSafeArea(.all)
    }

    @ViewBuilder
    private var dimmingOverlay: some View {
        if let img = frozenImage {
            Image(img, scale: 1, label: Text(""))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: screenFrame.width, height: screenFrame.height)
                .allowsHitTesting(false)      // parent ZStack owns all gestures
            if dimOverlay, let _ = selectionRect, isDragging {
                Color.black.opacity(0.35)
                    .allowsHitTesting(false)
            }
        } else if dimOverlay {
            if let rect = selectionRect, isDragging {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: CGSize(width: screenFrame.width, height: screenFrame.height)))
                    path.addRect(rect)
                }
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)      // parent ZStack owns all gestures
            } else {
                // The dim colour must NOT capture its own gestures — doing so blocks
                // the parent DragGesture and makes the overlay appear frozen.
                Color.black.opacity(0.3)
                    .allowsHitTesting(false)
            }
        }
        // dimOverlay = false: fully transparent — parent layer handles all interaction
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if let rect = selectionRect, isDragging {
            SelectionRectBorder(rect: rect)
            DimensionLabel(
                size: CGSize(width: rect.width, height: rect.height),
                near: CGPoint(x: rect.maxX, y: rect.minY)
            )
        }
    }

    @ViewBuilder
    private var magnifierOverlay: some View {
        if isDragging && showMagnifier {
            MagnifierView(
                mouseLocation: mouseLocation,
                windowOrigin: screenFrame.origin,
                windowHeight: screenFrame.height
            )
            .frame(width: 140, height: 140)
            .position(
                x: min(mouseLocation.x + 80, screenFrame.width - 70),
                y: max(mouseLocation.y - 80, 80)
            )
        }
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

struct DimensionLabel: View {
    let size: CGSize
    let near: CGPoint

    var body: some View {
        Text("\(Int(size.width)) × \(Int(size.height))")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.65))
            .cornerRadius(4)
            .position(
                x: near.x + 50,
                y: near.y - 16
            )
    }
}
