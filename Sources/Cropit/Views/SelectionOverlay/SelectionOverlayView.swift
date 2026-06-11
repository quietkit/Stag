import SwiftUI
import AppKit

enum CaptureMode {
    case area, recording, gif, ocr
    var actionLabel: String {
        switch self {
        case .area: return "Capture"
        case .recording: return "Record"
        case .gif: return "Create GIF"
        case .ocr: return "Scan"
        }
    }
}

struct SelectionOverlayView: View {
    let screenFrame: NSRect
    let frozenImage: CGImage?      // visible frozen background (freeze pref)
    var sampleImage: CGImage?      // clean source the loupe samples for true colors
    let onCapture: (CGRect) -> Void
    let onCancel: () -> Void
    var mode: CaptureMode = .area
    var dimOverlay: Bool = true   // false = Shottr "no-overlay" minimal mode
    var showMagnifier: Bool = true
    var showCrosshair: Bool = true
    var directCapture: Bool = false  // When true, auto-confirm; when false, show adjust UI

    private enum Phase { case idle, drawing, adjusting }
    private enum Handle { case tl, tr, bl, br, top, bottom, left, right, inside }

    @State private var phase: Phase = .idle
    @State private var selection: CGRect?
    @State private var drawStart: CGPoint?
    @State private var activeHandle: Handle?
    @State private var dragOrigin: CGRect?
    @State private var dragStartPoint: CGPoint?
    @State private var hovering = false
    @State private var mouseLocation: CGPoint = .zero
    @State private var hexColor: String?
    @State private var keyMonitor: Any?

    private let handleTolerance: CGFloat = 16
    private let minSize: CGFloat = 8

    private var bounds: CGSize { CGSize(width: screenFrame.width, height: screenFrame.height) }
    private var active: Bool { phase != .idle && selection != nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Drag lives on the base layer only, so the action-bar buttons (on top,
            // hit-testable) reliably receive clicks while dragging still works
            // everywhere else (the visual layers are allowsHitTesting(false)).
            Color.white.opacity(0.001)
                .contentShape(Rectangle())
                .gesture(dragGesture)
            dimmingOverlay
            crosshairGuides
            selectionVisuals
            magnifierOverlay
            actionBar
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                mouseLocation = p
                hovering = true
                // Update cursor based on handle hover
                if phase == .ended {
                    NSCursor.arrow.set()
                } else if let sel = selection, let handle = handleHit(at: p, rect: sel) {
                    updateCursorForHandle(handle)
                } else {
                    NSCursor.arrow.set()
                }
            case .ended:
                hovering = false
                NSCursor.arrow.set()
            }
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                mouseLocation = value.location
                switch phase {
                case .idle:
                    drawStart = value.startLocation
                    phase = .drawing
                    selection = makeRect(value.startLocation, value.location)
                case .drawing:
                    selection = makeRect(drawStart ?? value.startLocation, value.location)
                case .adjusting:
                    guard let sel = selection else { return }
                    if activeHandle == nil {
                        // Let the action bar's buttons handle their own clicks.
                        if actionBarRect(for: sel).contains(value.startLocation) { return }
                        if let h = handleHit(at: value.startLocation, rect: sel) {
                            activeHandle = h
                        } else if sel.contains(value.startLocation) {
                            activeHandle = .inside
                        } else {
                            // Started outside the selection → draw a fresh one.
                            phase = .drawing
                            drawStart = value.startLocation
                            selection = makeRect(value.startLocation, value.location)
                            return
                        }
                        dragOrigin = sel
                        dragStartPoint = value.startLocation
                    }
                    guard let origin = dragOrigin, let handle = activeHandle else { return }
                    if handle == .inside {
                        let dx = value.location.x - (dragStartPoint?.x ?? value.location.x)
                        let dy = value.location.y - (dragStartPoint?.y ?? value.location.y)
                        selection = clamp(origin.offsetBy(dx: dx, dy: dy))
                    } else {
                        selection = resize(origin, handle: handle, to: value.location)
                    }
                }
            }
            .onEnded { value in
                switch phase {
                case .drawing:
                    if let sel = selection, sel.width >= minSize, sel.height >= minSize {
                        selection = clamp(sel)
                        if directCapture {
                            // Auto-confirm immediately
                            onCapture(sel)
                        } else {
                            phase = .adjusting              // show adjust UI
                        }
                    } else {
                        selection = nil
                        phase = .idle                   // stray click: stay in overlay
                    }
                case .adjusting:
                    activeHandle = nil
                    dragOrigin = nil
                    dragStartPoint = nil
                case .idle:
                    break
                }
            }
    }

    private func confirm() {
        guard let sel = selection, sel.width >= minSize, sel.height >= minSize else { return }
        onCapture(sel)
    }

    // MARK: - Keyboard (arrows nudge, ⏎ confirm, esc cancel)

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53:                       // Esc
                onCancel(); return nil
            case 36, 76:                   // Return / keypad Enter
                confirm(); return nil
            case 123, 124, 125, 126:       // ← → ↓ ↑
                guard phase == .adjusting, var sel = selection else { return event }
                let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                switch event.keyCode {
                case 123: sel.origin.x -= step
                case 124: sel.origin.x += step
                case 125: sel.origin.y += step
                case 126: sel.origin.y -= step
                default: break
                }
                selection = clamp(sel)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: - Geometry helpers

    private func makeRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func clamp(_ r: CGRect) -> CGRect {
        var rect = r
        rect.size.width = min(rect.width, bounds.width)
        rect.size.height = min(rect.height, bounds.height)
        rect.origin.x = min(max(0, rect.origin.x), bounds.width - rect.width)
        rect.origin.y = min(max(0, rect.origin.y), bounds.height - rect.height)
        return rect
    }

    private func resize(_ r: CGRect, handle: Handle, to p: CGPoint) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        let px = min(max(0, p.x), bounds.width)
        let py = min(max(0, p.y), bounds.height)
        switch handle {
        case .tl:     minX = px; minY = py
        case .tr:     maxX = px; minY = py
        case .bl:     minX = px; maxY = py
        case .br:     maxX = px; maxY = py
        case .top:    minY = py
        case .bottom: maxY = py
        case .left:   minX = px
        case .right:  maxX = px
        case .inside: break
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                      width: abs(maxX - minX), height: abs(maxY - minY))
    }

    private func handlePoints(_ r: CGRect) -> [(Handle, CGPoint)] {
        [(.tl, CGPoint(x: r.minX, y: r.minY)),
         (.tr, CGPoint(x: r.maxX, y: r.minY)),
         (.bl, CGPoint(x: r.minX, y: r.maxY)),
         (.br, CGPoint(x: r.maxX, y: r.maxY)),
         (.top, CGPoint(x: r.midX, y: r.minY)),
         (.bottom, CGPoint(x: r.midX, y: r.maxY)),
         (.left, CGPoint(x: r.minX, y: r.midY)),
         (.right, CGPoint(x: r.maxX, y: r.midY))]
    }

    private func handleHit(at p: CGPoint, rect: CGRect) -> Handle? {
        for (h, c) in handlePoints(rect) where hypot(p.x - c.x, p.y - c.y) <= handleTolerance {
            return h
        }
        return nil
    }

    private func updateCursorForHandle(_ handle: Handle) {
        let cursor: NSCursor = switch handle {
        case .tl, .br: NSCursor.crosshair  // diagonal resize (no native diagonal, use crosshair)
        case .tr, .bl: NSCursor.crosshair
        case .top, .bottom: NSCursor.resizeUpDown
        case .left, .right: NSCursor.resizeLeftRight
        case .inside: NSCursor.openHand
        }
        cursor.set()
    }

    private func actionBarRect(for r: CGRect) -> CGRect {
        let w: CGFloat = 188, h: CGFloat = 40, gap: CGFloat = 14
        var y = r.maxY + gap + h / 2
        if y + h / 2 > bounds.height { y = r.minY - gap - h / 2 }   // flip above
        y = min(max(h / 2 + 4, y), bounds.height - h / 2 - 4)
        let x = min(max(w / 2 + 4, r.midX), bounds.width - w / 2 - 4)
        return CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
    }

    // MARK: - Layers

    // dim ON → darken outside the selection (crisp selection); dim OFF → minimal,
    // lightly dim the selection itself and keep the screen bright.
    @ViewBuilder
    private var dimmingOverlay: some View {
        let full = bounds
        if let img = frozenImage {
            Image(img, scale: 1, label: Text(""))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: full.width, height: full.height)
                .allowsHitTesting(false)
        }
        if let rect = selection, active {
            if dimOverlay {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: full))
                    p.addRect(rect)
                }
                .fill(Color.black.opacity(0.25), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }
        } else if dimOverlay {
            Color.black.opacity(0.15).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var crosshairGuides: some View {
        // Full-screen guide lines, controlled by the "Show crosshair" setting
        // (independent of the dim mode).
        if showCrosshair && (hovering || phase == .drawing) {
            CrosshairGuides(at: mouseLocation, size: bounds)
        }
    }

    @ViewBuilder
    private var selectionVisuals: some View {
        if let rect = selection, active {
            if dimOverlay {
                SelectionRectBorder(rect: rect)
                DimensionLabel(size: CGSize(width: rect.width, height: rect.height),
                               rect: rect, bounds: bounds)
            } else {
                MinimalSelectionBorder(rect: rect)
                MinimalSizeLabel(size: CGSize(width: rect.width, height: rect.height),
                                 at: mouseLocation, bounds: bounds)
            }
            if phase == .adjusting {
                SelectionHandles(points: handlePoints(rect).map { $0.1 })
            }
        }
    }

    @ViewBuilder
    private var magnifierOverlay: some View {
        if dimOverlay && showMagnifier && (hovering || phase == .drawing) {
            let block = magnifierPlacement()
            VStack(spacing: 6) {
                MagnifierView(viewPoint: mouseLocation, screenFrame: screenFrame,
                              frozenImage: sampleImage, hexColor: $hexColor)
                    .frame(width: 118, height: 118)
                MagnifierHUD(hex: hexColor, point: mouseLocation, selection: selection)
            }
            .position(x: block.x, y: block.y)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if phase == .adjusting, let rect = selection {
            let bar = actionBarRect(for: rect)
            let icon = mode == .recording ? "circle.fill" : mode == .gif ? "film.fill" : mode == .ocr ? "text.viewfinder" : "camera.fill"
            HStack(spacing: 8) {
                Button(action: confirm) {
                    Label(mode.actionLabel, systemImage: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)

                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .frame(width: bar.width, height: bar.height)
            .position(x: bar.midX, y: bar.midY)
        }
    }

    private func magnifierPlacement() -> CGPoint {
        let blockW: CGFloat = 130, blockH: CGFloat = 170, gap: CGFloat = 26
        var cx = mouseLocation.x + gap + blockW / 2
        if cx + blockW / 2 > screenFrame.width { cx = mouseLocation.x - gap - blockW / 2 }
        var cy = mouseLocation.y - gap - blockH / 2
        if cy - blockH / 2 < 0 { cy = mouseLocation.y + gap + blockH / 2 }
        cx = min(max(cx, blockW / 2 + 4), screenFrame.width - blockW / 2 - 4)
        cy = min(max(cy, blockH / 2 + 4), screenFrame.height - blockH / 2 - 4)
        return CGPoint(x: cx, y: cy)
    }
}

/// Eight resize handles drawn on the selection during the adjust phase.
struct SelectionHandles: View {
    let points: [CGPoint]
    var body: some View {
        Canvas { ctx, _ in
            for c in points {
                let r = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: r), with: .color(.white))
                ctx.stroke(Path(ellipseIn: r), with: .color(.black.opacity(0.55)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Thin selection outline for minimal (dim-off) mode — no corner brackets.
/// Double-stroked so it reads on both light and dark backgrounds.
struct MinimalSelectionBorder: View {
    let rect: CGRect
    var body: some View {
        Canvas { ctx, _ in
            let p = Path(rect)
            ctx.stroke(p, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5))
            ctx.stroke(p, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 0.75))
        }
        .allowsHitTesting(false)
    }
}

/// Small W×H readout that follows the cursor in minimal mode, clamped on-screen.
struct MinimalSizeLabel: View {
    let size: CGSize
    let at: CGPoint
    let bounds: CGSize
    var body: some View {
        Text("\(Int(size.width)) × \(Int(size.height))")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .position(x: min(at.x + 42, bounds.width - 36),
                      y: min(at.y + 24, bounds.height - 14))
            .allowsHitTesting(false)
    }
}

/// A detected window mapped into the overlay's view coordinate space.
struct WindowHit: Identifiable {
    let id = UUID()
    let rect: CGRect
    let title: String
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
            let border = Path(rect)
            ctx.stroke(border, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 3))
            ctx.stroke(border, with: .color(.white), style: StrokeStyle(lineWidth: 1.5))

            let arm: CGFloat = 16
            let corners: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: rect.minX, y: rect.minY),  arm,  arm),
                (CGPoint(x: rect.maxX, y: rect.minY), -arm,  arm),
                (CGPoint(x: rect.minX, y: rect.maxY),  arm, -arm),
                (CGPoint(x: rect.maxX, y: rect.maxY), -arm, -arm),
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

/// Size badge pinned to the selection's top-left, clamped on-screen.
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
        let above = rect.minY - badgeHeight / 2 - 4
        let y = above < 8 ? rect.minY + badgeHeight / 2 + 4 : above
        var x = rect.minX + estWidth / 2
        x = min(max(x, estWidth / 2 + 2), bounds.width - estWidth / 2 - 2)
        return CGPoint(x: x, y: y)
    }
}
