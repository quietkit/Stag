import SwiftUI

struct SelectionOverlayView: View {
    let screenFrame: NSRect
    let onCapture: (CGRect) -> Void
    let onCancel: () -> Void

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
                dimmingOverlay
                selectionOverlay
                magnifierOverlay
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onAppear { NSCursor.crosshair.push() }
            .onDisappear { NSCursor.crosshair.pop() }
        }
        .edgesIgnoringSafeArea(.all)
    }

    @ViewBuilder
    private var dimmingOverlay: some View {
        if let rect = selectionRect, isDragging {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: CGSize(width: screenFrame.width, height: screenFrame.height)))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
        } else {
            Color.black.opacity(0.3)
                .onTapGesture { }
        }
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
        if isDragging {
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
        ZStack {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            Path { path in
                for corner in cornerHandles(for: rect) {
                    path.addRect(corner)
                }
            }
            .fill(Color.white)
        }
    }

    private func cornerHandles(for r: CGRect) -> [CGRect] {
        let s: CGFloat = 6
        let inset: CGFloat = -3
        return [
            CGRect(x: r.minX + inset, y: r.minY + inset, width: s, height: s),
            CGRect(x: r.maxX + inset, y: r.minY + inset, width: s, height: s),
            CGRect(x: r.maxX + inset, y: r.maxY + inset, width: s, height: s),
            CGRect(x: r.minX + inset, y: r.maxY + inset, width: s, height: s),
        ]
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
