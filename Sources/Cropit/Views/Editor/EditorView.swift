import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

struct EditorView: View {
    let image: NSImage
    let window: NSWindow

    // Undo / Redo
    @State private var undoStack: [CanvasState] = []
    @State private var redoStack: [CanvasState] = []

    // Canvas state
    @State private var annotations: [Annotation] = []
    @State private var currentTool: DrawingTool = .arrow
    @State private var selectedAnnotationId: UUID?
    @State private var currentColor: Color = .white
    @State private var currentLineWidth: CGFloat = 2
    @State private var fillShapes = false

    // Transient drag state
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var isDrawing = false
    @State private var isMovingAnnotation = false
    @State private var moveStartAnnotation: Annotation?
    @State private var cursorLocation: CGPoint = .zero
    @State private var showingTextAlert = false
    @State private var freehandPoints: [CGPoint] = []
    @State private var pendingTextPosition: CGPoint = .zero
    @State private var textInput = ""
    @State private var stepCounter = 1

    // Emoji
    @State private var emojiPickerPresented = false
    @State private var pendingEmojiPosition: CGPoint = .zero

    // OCR result feedback
    @State private var ocrAlertMessage: String?

    // Upload state
    @State private var uploading = false
    @State private var uploadAlertMessage: String?
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero

    // Backdrop
    @State private var backdropEnabled = false
    @State private var backdropColor: Color = .white

    // Rotation
    @State private var rotation: CGFloat = 0

    private let toolBtn: CGFloat = 26
    private let toolbarH: CGFloat = 36
    private let footerH: CGFloat = 22
    private let minZoom: CGFloat = 0.1
    private let maxZoom: CGFloat = 10.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvasArea
            footer
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear(perform: installKeyboardMonitor)
    }

    // MARK: - Toolbar

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                imageLayer(geo: geo)
                annotationCanvas(geo: geo)
                if isDrawing {
                    livePreview(geo: geo)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .rotationEffect(.degrees(rotation))
            .padding(rotation != 0 ? 40 : 0)
            .gesture(canvasDragGesture(geo: geo))
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        let newZoom = zoomScale * scale.magnitude
                        zoomScale = min(maxZoom, max(minZoom, newZoom))
                    }
            )
            .onContinuousHover { phase in
                if case .moved(let pt) = phase { cursorLocation = pt }
            }
        }
        .popover(isPresented: $emojiPickerPresented, arrowEdge: .bottom) {
            emojiPickerView
        }
        .alert("Enter Text", isPresented: $showingTextAlert) {
            TextField("Text", text: $textInput)
            Button("OK") { addTextAnnotation() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("OCR Result", isPresented: Binding(
            get: { ocrAlertMessage != nil },
            set: { if !$0 { ocrAlertMessage = nil } }
        )) {
            Button("OK") { ocrAlertMessage = nil }
        } message: {
            Text(ocrAlertMessage ?? "")
        }
        .alert("Upload", isPresented: Binding(
            get: { uploadAlertMessage != nil },
            set: { if !$0 { uploadAlertMessage = nil } }
        )) {
            Button("OK") { uploadAlertMessage = nil }
        } message: {
            Text(uploadAlertMessage ?? "")
        }
    }

    private func installKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard window.isKeyWindow else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch (event.keyCode, mods) {
            case (6, _) where mods == [.command]: // ⌘Z
                undo()
                return nil
            case (6, _) where mods == [.command, .shift]: // ⇧⌘Z
                redo()
                return nil
            case (51, _), (117, _): // ⌫ or forward delete
                deleteSelected()
                return nil
            case (53, _): // Esc
                selectedAnnotationId = nil
                return nil
            case (24, _) where mods == [.command]: // ⌘=
                zoomIn()
                return nil
            case (27, _) where mods == [.command]: // ⌘-
                zoomOut()
                return nil
            case (0, _) where mods == [.command]: // ⌘0
                resetZoom()
                return nil
            default:
                break
            }
            // Tool shortcuts 0-9
            let toolMap: [UInt16: DrawingTool] = [
                18: .arrow, 19: .rect, 20: .circle, 21: .text,
                22: .blur, 23: .highlight, 24: .freehand, 25: .stepNumber,
                26: .mosaic, 29: .emoji, 27: .ruler
            ]
            if let tool = toolMap[event.keyCode], mods.isEmpty || mods == .shift {
                currentTool = tool
                return nil
            }
            return event
        }
    }

    // MARK: - Layers

    private func imageLayer(geo: GeometryProxy) -> some View {
        ZStack {
            if backdropEnabled {
                backdropColor
            }
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func annotationCanvas(geo: GeometryProxy) -> some View {
        Canvas { ctx, size in
            let (scale, offset) = computeTransform(geo: geo)
            for annotation in annotations {
                let isSelected = annotation.id == selectedAnnotationId
                renderAnnotation(annotation, ctx: &ctx, scale: scale, offset: offset, geo: geo, highlight: isSelected)
            }
        }
    }

    private func livePreview(geo: GeometryProxy) -> some View {
        Canvas { ctx, size in
            let (scale, offset) = computeTransform(geo: geo)
            guard let s = dragStart, let c = dragCurrent else { return }
            let previewAnnotation: Annotation
            if currentTool == .freehand {
                let pts = freehandPoints + [c]
                previewAnnotation = Annotation(type: .freehand(points: pts), color: currentColor, lineWidth: currentLineWidth)
            } else {
                previewAnnotation = Annotation(
                    type: previewType(from: s, to: c),
                    color: currentColor,
                    lineWidth: currentLineWidth
                )
            }
            renderAnnotation(previewAnnotation, ctx: &ctx, scale: scale, offset: offset, geo: geo, highlight: false)
        }
    }

    // MARK: - Rendering

    private func renderAnnotation(_ annotation: Annotation, ctx: inout GraphicsContext, scale: CGFloat, offset: CGSize, geo: GeometryProxy, highlight: Bool) {
        switch annotation.type {
        case .arrow(let start, let end):
            let sa = cgApply(start, scale: scale, offset: offset)
            let ea = cgApply(end, scale: scale, offset: offset)
            var path = Path()
            path.move(to: sa)
            path.addLine(to: ea)
            ctx.stroke(path, with: .color(annotation.color), lineWidth: annotation.lineWidth)
            let angle = atan2(ea.y - sa.y, ea.x - sa.x)
            let headLen: CGFloat = 12
            let headAngle: CGFloat = .pi / 7
            var arrow = Path()
            arrow.move(to: ea)
            arrow.addLine(to: CGPoint(x: ea.x - headLen * cos(angle - headAngle), y: ea.y - headLen * sin(angle - headAngle)))
            arrow.move(to: ea)
            arrow.addLine(to: CGPoint(x: ea.x - headLen * cos(angle + headAngle), y: ea.y - headLen * sin(angle + headAngle)))
            ctx.stroke(arrow, with: .color(annotation.color), lineWidth: annotation.lineWidth)
        case .rect(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized
            let vr = applyRect(r, scale: scale, offset: offset)
            if let fc = annotation.fillColor {
                ctx.fill(Path(vr), with: .color(fc))
            }
            ctx.stroke(Path(vr), with: .color(annotation.color), lineWidth: annotation.lineWidth)
        case .circle(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized
            let vr = applyRect(r, scale: scale, offset: offset)
            if let fc = annotation.fillColor {
                ctx.fill(Path(ellipseIn: vr), with: .color(fc))
            }
            ctx.stroke(Path(ellipseIn: vr), with: .color(annotation.color), lineWidth: annotation.lineWidth)
        case .text(let pos, let text, let fontSize):
            let p = cgApply(pos, scale: scale, offset: offset)
            ctx.draw(Text(text).font(.system(size: fontSize * scale)).foregroundColor(annotation.color), at: p, anchor: .topLeading)
        case .blur(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized
            let vr = applyRect(r, scale: scale, offset: offset)
            ctx.fill(Path(vr), with: .color(.black.opacity(0.25)))
            ctx.stroke(Path(vr), with: .color(annotation.color.opacity(0.5)), lineWidth: 1)
            let center = CGPoint(x: vr.midX, y: vr.midY)
            ctx.draw(Text("●").font(.system(size: 20)).foregroundColor(.white.opacity(0.6)), at: center, anchor: .center)
        case .highlight(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized
            let vr = applyRect(r, scale: scale, offset: offset)
            ctx.fill(Path(vr), with: .color(annotation.color.opacity(0.3)))
            ctx.stroke(Path(vr), with: .color(annotation.color.opacity(0.6)), lineWidth: 1)
        case .freehand(let points):
            guard points.count > 1 else {
                if let pt = points.first {
                    let p = cgApply(pt, scale: scale, offset: offset)
                    ctx.fill(Path(ellipseIn: CGRect(origin: p, size: .zero).insetBy(dx: -2, dy: -2)), with: .color(annotation.color))
                }
                return
            }
            var path = Path()
            let first = cgApply(points[0], scale: scale, offset: offset)
            path.move(to: first)
            for pt in points.dropFirst() {
                path.addLine(to: cgApply(pt, scale: scale, offset: offset))
            }
            ctx.stroke(path, with: .color(annotation.color), lineWidth: annotation.lineWidth)
        case .stepNumber(let center, let number):
            let p = cgApply(center, scale: scale, offset: offset)
            let r = CGRect(origin: p, size: .zero).insetBy(dx: -16 * scale, dy: -16 * scale)
            ctx.fill(Path(ellipseIn: r), with: .color(annotation.color))
            ctx.draw(Text("\(number)").font(.system(size: 16 * scale, weight: .bold)).foregroundColor(.white), at: p, anchor: .center)
        case .mosaic(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized
            let vr = applyRect(r, scale: scale, offset: offset)
            ctx.fill(Path(vr), with: .color(.black.opacity(0.2)))
            ctx.stroke(Path(vr), with: .color(annotation.color.opacity(0.6)), lineWidth: 1)
            let center = CGPoint(x: vr.midX, y: vr.midY)
            ctx.draw(Text("⊞").font(.system(size: 20)).foregroundColor(.white.opacity(0.6)), at: center, anchor: .center)
        case .emoji(let pos, let text, let fontSize):
            let p = cgApply(pos, scale: scale, offset: offset)
            ctx.draw(Text(text).font(.system(size: fontSize * scale)).foregroundColor(annotation.color), at: p, anchor: .center)
        case .ruler(let start, let end):
            let sa = cgApply(start, scale: scale, offset: offset)
            let ea = cgApply(end, scale: scale, offset: offset)
            var path = Path()
            path.move(to: sa)
            path.addLine(to: ea)
            ctx.stroke(path, with: .color(annotation.color), lineWidth: annotation.lineWidth)
            // Tick marks at ends
            let angle = atan2(ea.y - sa.y, ea.x - sa.x)
            let tickLen: CGFloat = 6 * scale
            for pt in [sa, ea] {
                var tick = Path()
                tick.move(to: CGPoint(x: pt.x - tickLen * sin(angle), y: pt.y + tickLen * cos(angle)))
                tick.addLine(to: CGPoint(x: pt.x + tickLen * sin(angle), y: pt.y - tickLen * cos(angle)))
                ctx.stroke(tick, with: .color(annotation.color), lineWidth: annotation.lineWidth)
            }
            // Distance label
            let dist = hypot(end.x - start.x, end.y - start.y)
            let label = "\(Int(dist))px"
            let mid = CGPoint(x: (sa.x + ea.x) / 2, y: (sa.y + ea.y) / 2 - 8 * scale)
            ctx.draw(Text(label).font(.system(size: 11 * scale, weight: .medium)).foregroundColor(annotation.color), at: mid, anchor: .center)
        case .spotlight(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized
            let vr = applyRect(r, scale: scale, offset: offset)
            ctx.fill(Path(vr), with: .color(.white.opacity(0.15)))
            ctx.stroke(Path(ellipseIn: vr), with: .color(annotation.color), lineWidth: 2)
        }

        if highlight {
            let hr = highlightRect(annotation: annotation, scale: scale, offset: offset)
            ctx.stroke(Path(hr), with: .color(.yellow.opacity(0.7)), lineWidth: 1.5)
        }
    }

    private func highlightRect(annotation: Annotation, scale: CGFloat, offset: CGSize) -> CGRect {
        let h: CGFloat = 8
        switch annotation.type {
        case .arrow(let start, let end):
            var r = CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized
            r = r.insetBy(dx: -h, dy: -h)
            return applyRect(r, scale: scale, offset: offset)
        case .rect(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized.insetBy(dx: -h, dy: -h)
            return applyRect(r, scale: scale, offset: offset)
        case .circle(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized.insetBy(dx: -h, dy: -h)
            return applyRect(r, scale: scale, offset: offset)
        case .text(let pos, let text, let fontSize):
            let approx = CGSize(width: CGFloat(text.count) * fontSize * 0.6, height: fontSize * 1.4)
            let r = CGRect(origin: pos, size: approx).insetBy(dx: -h, dy: -h)
            return applyRect(r, scale: scale, offset: offset)
        case .blur(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized.insetBy(dx: -h, dy: -h)
            return applyRect(r, scale: scale, offset: offset)
        case .highlight(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized.insetBy(dx: -h, dy: -h)
            return applyRect(r, scale: scale, offset: offset)
        case .freehand(let points):
            guard !points.isEmpty else { return .zero }
            let xs = points.map(\.x); let ys = points.map(\.y)
            let r = CGRect(x: xs.min()! - h, y: ys.min()! - h, width: xs.max()! - xs.min()! + 2*h, height: ys.max()! - ys.min()! + 2*h)
            return applyRect(r, scale: scale, offset: offset)
        case .stepNumber(let center, _):
            let r = CGRect(origin: center, size: .zero).insetBy(dx: -20 - h, dy: -20 - h)
            return applyRect(r, scale: scale, offset: offset)
        case .mosaic(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized.insetBy(dx: -h, dy: -h)
            return applyRect(r, scale: scale, offset: offset)
        case .emoji(let pos, _, let fontSize):
            let approx = CGSize(width: fontSize * 1.2, height: fontSize * 1.2)
            let r = CGRect(origin: pos, size: approx).insetBy(dx: -h, dy: -h)
            return applyRect(r, scale: scale, offset: offset)
        case .ruler(let start, let end):
            var r = CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized
            r = r.insetBy(dx: -h, dy: -h)
            return applyRect(r, scale: scale, offset: offset)
        case .spotlight(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized.insetBy(dx: -h, dy: -h)
            return applyRect(r, scale: scale, offset: offset)
        }
    }

    // MARK: - Coordinate helpers

    private func computeTransform(geo: GeometryProxy) -> (CGFloat, CGSize) {
        let imgSize = image.size
        let baseScale = min(geo.size.width / imgSize.width, geo.size.height / imgSize.height)
        let scale = baseScale * zoomScale
        let offset = CGSize(
            width: (geo.size.width - imgSize.width * scale) / 2 + panOffset.width,
            height: (geo.size.height - imgSize.height * scale) / 2 + panOffset.height
        )
        return (scale, offset)
    }

    private func cgApply(_ point: CGPoint, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width, y: point.y * scale + offset.height)
    }

    private func applyRect(_ rect: CGRect, scale: CGFloat, offset: CGSize) -> CGRect {
        CGRect(
            origin: CGPoint(x: rect.origin.x * scale + offset.width, y: rect.origin.y * scale + offset.height),
            size: CGSize(width: rect.width * scale, height: rect.height * scale)
        )
    }

    private func canvasPoint(from viewPoint: CGPoint, geo: GeometryProxy) -> CGPoint {
        let (scale, offset) = computeTransform(geo: geo)
        return CGPoint(
            x: (viewPoint.x - offset.width) / scale,
            y: (viewPoint.y - offset.height) / scale
        )
    }

    private func previewType(from start: CGPoint, to end: CGPoint) -> AnnotationType {
        switch currentTool {
        case .arrow: return .arrow(start: start, end: end)
        case .rect:  return .rect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .circle: return .circle(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .highlight: return .highlight(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .blur:  return .blur(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .mosaic: return .mosaic(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .spotlight: return .spotlight(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .ruler: return .ruler(start: start, end: end)
        default: return .arrow(start: start, end: end)
        }
    }

    // MARK: - Gesture

    private func canvasDragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let pt = canvasPoint(from: value.location, geo: geo)

                if isMovingAnnotation, let _ = selectedAnnotationId {
                    // Move the selected annotation by delta
                    if let start = dragStart, let orig = moveStartAnnotation {
                        let delta = CGSize(width: pt.x - start.x, height: pt.y - start.y)
                        if let idx = annotations.firstIndex(where: { $0.id == selectedAnnotationId }) {
                            annotations[idx] = orig.offsetBy(delta)
                        }
                    }
                    return
                }

                // First move — check if we're on a selected annotation
                if value.translation.width == 0 && value.translation.height == 0 {
                    if let selId = selectedAnnotationId,
                       let selAnn = annotations.first(where: { $0.id == selId }),
                       selAnn.contains(point: pt) {
                        isMovingAnnotation = true
                        dragStart = pt
                        moveStartAnnotation = selAnn
                        return
                    }
                }

                // Check if tapping on an annotation (selection)
                if value.translation.width == 0 && value.translation.height == 0 {
                    let tapped = annotations.last(where: { $0.contains(point: pt) })
                    if let tapped = tapped {
                        selectedAnnotationId = tapped.id
                        return
                    } else {
                        selectedAnnotationId = nil
                    }
                }

                switch currentTool {
                case .blur:
                    if !isDrawing {
                        dragStart = pt
                        isDrawing = true
                    }
                    dragCurrent = pt
                case .text:
                    if value.translation.width == 0 && value.translation.height == 0 {
                        pendingTextPosition = pt
                        textInput = ""
                        showingTextAlert = true
                    }
                case .freehand:
                    if !isDrawing {
                        dragStart = pt
                        dragCurrent = pt
                        freehandPoints = [pt]
                        isDrawing = true
                    } else {
                        dragCurrent = pt
                        freehandPoints.append(pt)
                    }
                default:
                    if !isDrawing {
                        dragStart = pt
                        isDrawing = true
                    }
                    dragCurrent = pt
                }
            }
            .onEnded { value in
                defer {
                    isDrawing = false
                    isMovingAnnotation = false
                    dragStart = nil
                    dragCurrent = nil
                    moveStartAnnotation = nil
                    freehandPoints = []
                }
                if isMovingAnnotation { pushUndo(); return }
                guard isDrawing, let s = dragStart else { return }
                let pt = canvasPoint(from: value.location, geo: geo)

                let fc: Color? = fillShapes && [.rect, .circle].contains(currentTool) ? currentColor.opacity(0.25) : nil
                pushUndo()
                switch currentTool {
                case .blur:
                    let r = CGRect(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)).standardized
                    guard r.width > 5 && r.height > 5 else { return }
                    annotations.append(Annotation(type: .blur(origin: r.origin, size: r.size), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .arrow:
                    annotations.append(Annotation(type: .arrow(start: s, end: pt), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .rect:
                    annotations.append(Annotation(type: .rect(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .circle:
                    annotations.append(Annotation(type: .circle(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .highlight:
                    let r = CGRect(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)).standardized
                    guard r.width > 5 && r.height > 5 else { return }
                    annotations.append(Annotation(type: .highlight(origin: r.origin, size: r.size), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .freehand:
                    annotations.append(Annotation(type: .freehand(points: freehandPoints), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .stepNumber:
                    annotations.append(Annotation(type: .stepNumber(center: pt, number: stepCounter), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                    stepCounter += 1
                case .text:
                    break
                case .mosaic:
                    let r = CGRect(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)).standardized
                    guard r.width > 5 && r.height > 5 else { return }
                    annotations.append(Annotation(type: .mosaic(origin: r.origin, size: r.size), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .emoji:
                    pendingEmojiPosition = pt
                    emojiPickerPresented = true
                case .ruler:
                    annotations.append(Annotation(type: .ruler(start: s, end: pt), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .spotlight:
                    let r = CGRect(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)).standardized
                    guard r.width > 5 && r.height > 5 else { return }
                    annotations.append(Annotation(type: .spotlight(origin: r.origin, size: r.size), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                }
            }
    }

    private func interpolatePoints(from: CGPoint, to: CGPoint) -> [CGPoint] {
        let dist = hypot(to.x - from.x, to.y - from.y)
        let steps = max(1, Int(dist / 2))
        guard steps > 1 else { return [from] }
        var pts: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            pts.append(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        }
        return pts
    }

    private func addTextAnnotation() {
        guard !textInput.isEmpty else { return }
        pushUndo()
        annotations.append(Annotation(type: .text(position: pendingTextPosition, text: textInput, fontSize: 18), color: currentColor, fillColor: nil, lineWidth: currentLineWidth))
        textInput = ""
    }

    private var emojiPickerView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
            ForEach(commonEmojis, id: \.self) { emoji in
                Button {
                    addEmojiAnnotation(emoji)
                    emojiPickerPresented = false
                } label: {
                    Text(emoji)
                        .font(.system(size: 22))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 320)
    }

    private func addEmojiAnnotation(_ emoji: String) {
        pushUndo()
        annotations.append(Annotation(type: .emoji(position: pendingEmojiPosition, text: emoji, fontSize: 36), color: currentColor, fillColor: nil, lineWidth: currentLineWidth))
    }

    // MARK: - Zoom

    private func zoomIn() {
        zoomScale = min(maxZoom, zoomScale * 1.25)
    }

    private func zoomOut() {
        zoomScale = max(minZoom, zoomScale / 1.25)
    }

    private func resetZoom() {
        zoomScale = 1.0
        panOffset = .zero
    }

    private func rotate(_ degrees: CGFloat) {
        guard rotation != degrees else { return }
        pushUndo()
        rotation = degrees
    }

    // MARK: - Undo / Redo / Delete

    private func pushUndo() {
        undoStack.append(CanvasState(annotations: annotations, currentTool: currentTool, selectedAnnotationId: selectedAnnotationId, rotation: rotation))
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(CanvasState(annotations: annotations, currentTool: currentTool, selectedAnnotationId: selectedAnnotationId, rotation: rotation))
        let state = undoStack.removeLast()
        annotations = state.annotations
        currentTool = state.currentTool
        selectedAnnotationId = state.selectedAnnotationId
        rotation = state.rotation
    }

    private func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(CanvasState(annotations: annotations, currentTool: currentTool, selectedAnnotationId: selectedAnnotationId, rotation: rotation))
        let state = redoStack.removeLast()
        annotations = state.annotations
        currentTool = state.currentTool
        selectedAnnotationId = state.selectedAnnotationId
        rotation = state.rotation
    }

    private func deleteSelected() {
        guard let id = selectedAnnotationId else { return }
        pushUndo()
        annotations.removeAll { $0.id == id }
        selectedAnnotationId = nil
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            toolGroup([.arrow, .rect, .circle])
            toolbarDivider
            toolGroup([.freehand, .highlight])
            toolbarDivider
            toolGroup([.blur, .stepNumber, .text])
            toolbarDivider
            toolGroup([.mosaic, .emoji, .ruler, .spotlight])
            toolbarDivider
            fillToggle
            toolbarDivider
            colorStrip
            colorPickerButton
            toolbarDivider
            lineWidthControl
            toolbarDivider
            zoomControls
            toolbarDivider
            rotateControls
            toolbarDivider
            actionButtons
        }
        .frame(height: toolbarH)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial)
    }

    private func toolGroup(_ tools: [DrawingTool]) -> some View {
        HStack(spacing: 1) {
            ForEach(tools, id: \.self) { tool in
                toolButton(tool)
            }
        }
        .padding(.horizontal, 3)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    private func toolButton(_ tool: DrawingTool) -> some View {
        Button {
            currentTool = tool
        } label: {
            Image(systemName: toolIcon(tool))
                .font(.system(size: 12))
                .foregroundColor(currentTool == tool ? .white : .secondary)
                .frame(width: toolBtn, height: toolBtn)
                .background(currentTool == tool ? Color.accentColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("\(tool.rawValue.capitalized) (\(toolShortcut(tool)))")
    }

    private func toolIcon(_ tool: DrawingTool) -> String {
        switch tool {
        case .arrow:      return "arrow.up.right"
        case .rect:       return "rectangle"
        case .circle:     return "circle"
        case .text:       return "textformat"
        case .blur:       return "eye.slash"
        case .highlight:  return "highlighter"
        case .freehand:   return "pencil.tip"
        case .stepNumber: return "number"
        case .mosaic:     return "square.grid.3x3"
        case .emoji:      return "face.smiling"
        case .ruler:      return "ruler"
        case .spotlight:  return "circle.circle"
        }
    }

    private func toolShortcut(_ tool: DrawingTool) -> String {
        let map: [DrawingTool: String] = [
            .arrow: "1", .rect: "2", .circle: "3", .text: "4",
            .blur: "5", .highlight: "6", .freehand: "7", .stepNumber: "8",
            .mosaic: "9", .emoji: "0"
        ]
        return map[tool] ?? ""
    }

    private var fillToggle: some View {
        Button {
            fillShapes.toggle()
        } label: {
            Image(systemName: fillShapes ? "square.fill" : "square")
                .font(.system(size: 11))
                .foregroundColor(fillShapes ? .accentColor : .secondary)
                .frame(width: 22, height: 22)
                .background(fillShapes ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("Fill shapes (\(fillShapes ? "ON" : "OFF"))")
        .padding(.horizontal, 4)
    }

    private var colorStrip: some View {
        HStack(spacing: 3) {
            ForEach(editorColors, id: \.self) { color in
                colorSwatch(color)
            }
        }
        .padding(.horizontal, 6)
    }

    private func colorSwatch(_ color: Color) -> some View {
        Button {
            currentColor = color
        } label: {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(currentColor == color ? Color.primary : Color.white.opacity(0.3), lineWidth: currentColor == color ? 2 : 0.5)
                )
                .shadow(color: color.opacity(0.3), radius: currentColor == color ? 3 : 0)
        }
        .buttonStyle(.plain)
        .help(colorHex(color))
    }

    private func colorHex(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        let r = Int(ns.redComponent * 255)
        let g = Int(ns.greenComponent * 255)
        let b = Int(ns.blueComponent * 255)
        return "#\(String(format: "%02X%02X%02X", r, g, b))"
    }

    private var colorPickerButton: some View {
        ColorPicker("", selection: $currentColor, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 22, height: 22)
            .scaleEffect(0.7)
            .help("Pick custom color")
            .padding(.horizontal, 4)
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Zoom Out (⌘-)")

            Text("\(Int(zoomScale * 100))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32)

            Button { zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Zoom In (⌘=)")

            Button { resetZoom() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .help("Reset Zoom (⌘0)")
            .disabled(zoomScale == 1.0)
        }
        .padding(.horizontal, 4)
    }

    private var rotateControls: some View {
        HStack(spacing: 2) {
            Button { rotate(-90) } label: {
                Image(systemName: "rotate.left")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Rotate Left")

            Text("\(Int(rotation))°")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 28)

            Button { rotate(90) } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Rotate Right")

            if rotation != 0 {
                Button { rotate(0) } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .help("Reset Rotation")
            }
        }
        .padding(.horizontal, 4)
    }

    private var lineWidthControl: some View {
        HStack(spacing: 4) {
            Text("\(Int(currentLineWidth))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 14)
            // Visual stroke preview
            RoundedRectangle(cornerRadius: 1)
                .fill(currentColor)
                .frame(width: 16, height: max(1, min(currentLineWidth, 12)))
            Slider(value: $currentLineWidth, in: 1...12, step: 1)
                .frame(width: 40)
                .controlSize(.mini)
        }
        .padding(.horizontal, 6)
    }

    private var actionButtons: some View {
        HStack(spacing: 1) {
            actionButton("arrow.uturn.backward", "Undo (⌘Z)", undo, !undoStack.isEmpty)
            actionButton("arrow.uturn.forward", "Redo (⇧⌘Z)", redo, !redoStack.isEmpty)
            actionButton("trash", "Delete (⌫)", deleteSelected, selectedAnnotationId != nil)
            toolbarDivider
            actionButton("doc.on.clipboard", "Copy (⌘C)", exportAndCopy, true)
            actionButton("text.viewfinder", "OCR", performOCR, true)
            actionButton("square.and.arrow.down", "Save (⌘S)", exportAndSave, true)
            let hasUploadURL = !AppStore.shared.preferences.uploadURL.isEmpty
            actionButton("icloud.and.arrow.up", uploading ? "Uploading…" : "Upload", uploadImage, hasUploadURL && !uploading)
        }
        .padding(.horizontal, 4)
    }

    private func actionButton(_ icon: String, _ help: String, _ action: @escaping () -> Void, _ enabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    // MARK: - Export

    private func exportAndCopy() {
        guard let exported = exportImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([exported])
    }

    private func exportAndSave() {
        guard let exported = exportImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Cropit_\(Date().shotTimestamp).png"
        panel.beginSheetModal(for: window) { resp in
            guard resp == .OK, let url = panel.url else { return }
            exported.pngWrite(to: url)
        }
    }

    private func exportImage() -> NSImage? {
        let imgSize = image.size
        let angleRad = rotation * .pi / 180
        let cosAngle = abs(cos(angleRad))
        let sinAngle = abs(sin(angleRad))
        let rotatedSize = NSSize(
            width: imgSize.width * cosAngle + imgSize.height * sinAngle,
            height: imgSize.width * sinAngle + imgSize.height * cosAngle
        )
        let result = NSImage(size: rotatedSize)
        result.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return nil
        }
        ctx.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        ctx.rotate(by: angleRad)
        ctx.translateBy(x: -imgSize.width / 2, y: -imgSize.height / 2)

        if backdropEnabled {
            ctx.setFillColor(NSColor(backdropColor).cgColor)
            ctx.fill(CGRect(origin: .zero, size: imgSize))
        } else {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
            ctx.fill(CGRect(origin: .zero, size: imgSize))
        }
        image.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)

        for annotation in annotations {
            ctx.setStrokeColor(annotation.color.cgColor ?? CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.setLineWidth(annotation.lineWidth)

            switch annotation.type {
            case .arrow(let start, let end):
                drawArrow(on: ctx, from: start, to: end, annotation: annotation)
            case .rect(let origin, let size):
                let rr = CGRect(origin: origin, size: size).standardized
                if let fc = annotation.fillColor {
                    ctx.setFillColor(fc.cgColor ?? CGColor(red: 0, green: 0, blue: 1, alpha: 0.25))
                    ctx.fill(rr)
                }
                ctx.stroke(rr)
            case .circle(let origin, let size):
                let ce = CGRect(origin: origin, size: size).standardized
                if let fc = annotation.fillColor {
                    ctx.setFillColor(fc.cgColor ?? CGColor(red: 0, green: 0, blue: 1, alpha: 0.25))
                    ctx.fillEllipse(in: ce)
                }
                ctx.strokeEllipse(in: ce)
            case .text(let pos, let text, let fontSize):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor(annotation.color)
                ]
                text.draw(at: pos, withAttributes: attrs)
            case .blur(let origin, let size):
                applyRealBlur(on: ctx, rect: CGRect(origin: origin, size: size).standardized, imageSize: imgSize)
            case .highlight(let origin, let size):
                ctx.setFillColor((annotation.color.cgColor ?? CGColor(red: 1, green: 1, blue: 0, alpha: 1)).copy(alpha: 0.3)!)
                ctx.fill(CGRect(origin: origin, size: size).standardized)
            case .freehand(let points):
                guard points.count > 1 else { break }
                ctx.move(to: points[0])
                for pt in points.dropFirst() {
                    ctx.addLine(to: pt)
                }
                ctx.strokePath()
            case .stepNumber(let center, let number):
                let r = CGRect(origin: center, size: .zero).insetBy(dx: -16, dy: -16)
                ctx.setFillColor(annotation.color.cgColor ?? CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
                ctx.fillEllipse(in: r)
                let text = "\(number)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let textSize = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2), withAttributes: attrs)
            case .mosaic(let origin, let size):
                applyRealMosaic(on: ctx, rect: CGRect(origin: origin, size: size).standardized, imageSize: imgSize)
            case .emoji(let pos, let emojiChar, let fontSize):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor(annotation.color)
                ]
                let textSize = emojiChar.size(withAttributes: attrs)
                emojiChar.draw(at: CGPoint(x: pos.x - textSize.width / 2, y: pos.y - textSize.height / 2), withAttributes: attrs)
            case .ruler(let start, let end):
                drawRuler(on: ctx, from: start, to: end, annotation: annotation)
            case .spotlight(let origin, let size):
                applySpotlight(on: ctx, rect: CGRect(origin: origin, size: size).standardized, imageSize: imgSize)
            }
        }
        result.unlockFocus()
        return result
    }

    private func performOCR() {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let request = VNRecognizeTextRequest { request, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.ocrAlertMessage = "OCR failed: \(error.localizedDescription)"
                    return
                }
                let texts = (request.results as? [VNRecognizedTextObservation])?.compactMap { obs in
                    obs.topCandidates(1).first?.string
                } ?? []
                let result = texts.joined(separator: "\n")
                guard !result.isEmpty else {
                    self.ocrAlertMessage = "No text found in image."
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result, forType: .string)
                self.ocrAlertMessage = "Copied \(texts.count) line(s) to clipboard."
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    private func uploadImage() {
        guard let exported = exportImage(), let png = exported.pngData else { return }
        let urlStr = AppStore.shared.preferences.uploadURL
        guard let url = URL(string: urlStr) else { return }

        uploading = true
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("image/png", forHTTPHeaderField: "Content-Type")
        req.httpBody = png

        URLSession.shared.dataTask(with: req) { data, resp, error in
            DispatchQueue.main.async {
                self.uploading = false
                if let error = error {
                    self.uploadAlertMessage = "Upload failed: \(error.localizedDescription)"
                    return
                }
                guard let data = data, let responseStr = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !responseStr.isEmpty
                else {
                    self.uploadAlertMessage = "Uploaded (empty response)."
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(responseStr, forType: .string)
                self.uploadAlertMessage = "URL copied to clipboard."
            }
        }.resume()
    }

    private func drawArrow(on ctx: CGContext, from start: CGPoint, to end: CGPoint, annotation: Annotation) {
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLen: CGFloat = 14
        let headAngle: CGFloat = .pi / 7
        ctx.move(to: end)
        ctx.addLine(to: CGPoint(x: end.x - headLen * cos(angle - headAngle), y: end.y - headLen * sin(angle - headAngle)))
        ctx.move(to: end)
        ctx.addLine(to: CGPoint(x: end.x - headLen * cos(angle + headAngle), y: end.y - headLen * sin(angle + headAngle)))
        ctx.strokePath()
    }

    private func drawRuler(on ctx: CGContext, from start: CGPoint, to end: CGPoint, annotation: Annotation) {
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let tickLen: CGFloat = 8
        // Ticks at both ends
        for pt in [start, end] {
            ctx.move(to: CGPoint(x: pt.x - tickLen * sin(angle), y: pt.y + tickLen * cos(angle)))
            ctx.addLine(to: CGPoint(x: pt.x + tickLen * sin(angle), y: pt.y - tickLen * cos(angle)))
            ctx.strokePath()
        }

        let dist = hypot(end.x - start.x, end.y - start.y)
        let label = "\(Int(dist))px"
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 10)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(annotation.color)
        ]
        let labelSize = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: mid.x - labelSize.width / 2, y: mid.y - labelSize.height / 2), withAttributes: attrs)
    }

    private func applyRealBlur(on ctx: CGContext, rect: CGRect, imageSize: NSSize) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let ciImage = CIImage(cgImage: cgImage)
        // Crop to the blur region first, then apply blur so output extent stays manageable
        let flippedY = imageSize.height - rect.maxY
        let cropRect = CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
        let cropped = ciImage.cropped(to: cropRect)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = cropped
        filter.radius = 12
        guard let blurred = filter.outputImage else { return }
        let ciCtx = CIContext(cgContext: ctx, options: nil)
        // Blur extends the image; clamp the draw rect back to the original crop bounds
        let drawRect = CGRect(origin: cropRect.origin, size: blurred.extent.size)
        ciCtx.draw(blurred, in: drawRect, from: blurred.extent)
    }

    private func applyRealMosaic(on ctx: CGContext, rect: CGRect, imageSize: NSSize) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let ciImage = CIImage(cgImage: cgImage)
        let flippedY = imageSize.height - rect.maxY
        let cropRect = CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
        let cropped = ciImage.cropped(to: cropRect)
        let filter = CIFilter.pixellate()
        filter.inputImage = cropped
        filter.scale = Float(max(8, min(rect.width, rect.height) / 8))
        guard let pixellated = filter.outputImage else { return }
        let ciCtx = CIContext(cgContext: ctx, options: nil)
        ciCtx.draw(pixellated, in: CGRect(origin: cropRect.origin, size: cropped.extent.size), from: pixellated.extent)
    }

    private func applySpotlight(on ctx: CGContext, rect: CGRect, imageSize: NSSize) {
        let fullRect = CGRect(origin: .zero, size: imageSize)
        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        ctx.addRect(fullRect)
        ctx.addEllipse(in: rect)
        ctx.drawPath(using: .eoFill)
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: rect)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Label("\(Int(cursorLocation.x)), \(Int(cursorLocation.y))", systemImage: "cursor.rays")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Label("\(annotations.count) annotations", systemImage: "pencil")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            if fillShapes {
                Label("Fill", systemImage: "square.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
            }
            Spacer()
            backdropControl
        }
        .padding(.horizontal, 10)
        .frame(height: footerH)
        .background(.ultraThinMaterial)
    }

    private var backdropControl: some View {
        HStack(spacing: 4) {
            Button {
                backdropEnabled.toggle()
            } label: {
                Image(systemName: backdropEnabled ? "rectangle.fill" : "rectangle")
                    .font(.system(size: 10))
                    .foregroundColor(backdropEnabled ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(backdropEnabled ? "Hide backdrop" : "Show backdrop")

            if backdropEnabled {
                ColorPicker("", selection: $backdropColor, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
        }
    }
}

// MARK: - Hover helper (unchanged)

extension View {
    func onContinuousHover(_ handler: @escaping (HoverPhase) -> Void) -> some View {
        self.background(ContinuousHoverRepresentable(handler: handler))
    }
}

struct ContinuousHoverRepresentable: NSViewRepresentable {
    let handler: (HoverPhase) -> Void

    func makeNSView(context: Context) -> NSView {
        HoverTrackingView(handler: handler)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class HoverTrackingView: NSView {
    let handler: (HoverPhase) -> Void
    private var trackingArea: NSTrackingArea?

    init(handler: @escaping (HoverPhase) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        handler(.moved(convert(event.locationInWindow, from: nil)))
    }
}

enum HoverPhase {
    case moved(CGPoint)
}
