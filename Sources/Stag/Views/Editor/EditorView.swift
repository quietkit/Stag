import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

struct EditorView: View {
    let image: NSImage
    let window: NSWindow
    let filePath: String?

    @State private var workingImage: NSImage

    init(image: NSImage, window: NSWindow, filePath: String? = nil) {
        self.image = image
        self.window = window
        self.filePath = filePath
        _workingImage = State(initialValue: image)
    }

    // Undo / Redo
    @State private var canvasHistory = CanvasHistory()

    // Canvas state
    @State private var annotations: [Annotation] = []
    @State private var currentTool: DrawingTool = .rect
    @State private var selectedAnnotationId: UUID?
    @State private var currentColor: Color = .red
    @State private var currentLineWidth: CGFloat = 2
    @State private var currentLineStyle: LineStyle = .solid
    @State private var currentArrowHeadStyle: ArrowHeadStyle = .standard
    @State private var fillShapes = false

    // Color history (last 8 used colors)
    @State private var colorHistory: [Color] = []

    // Transient drag state
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var isDrawing = false
    @State private var isMovingAnnotation = false
    @State private var isResizingAnnotation = false
    @State private var resizeHandleIndex: Int = -1
    @State private var resizeStartAnnotation: Annotation?
    @State private var moveStartAnnotation: Annotation?
    @State private var cursorLocation: CGPoint = .zero
    @State private var showingTextAlert = false
    @State private var freehandPoints: [CGPoint] = []
    @State private var pendingTextPosition: CGPoint = .zero
    @State private var textInput = ""
    @State private var stepCounter = 1
    @State private var textFontSize: CGFloat = 24
    @State private var textStyle: TextStyle = .regular
    @State private var blurRadius: CGFloat = 12

    // Emoji
    @State private var emojiPickerPresented = false
    @State private var pendingEmojiPosition: CGPoint = .zero

    // OCR result feedback
    @State private var ocrAlertMessage: String?

    // Upload state
    @State private var uploading = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0      // pinch anchor
    @State private var panOffset: CGSize = .zero
    @State private var scrollMonitor: Any? = nil

    // Backdrop
    @State private var backdrop = BackdropStyle()

    // Rotation
    @State private var rotation: CGFloat = 0

    // Image undo stack (for destructive edits)
    @State private var imageHistory = BoundedHistory<NSImage>(limit: 20)
    @State private var cloneStampSource: CGPoint?
    @State private var removeBgRunning = false
    @State private var eraserSwipePoints: [CGPoint] = []

    // Keyboard monitor token
    @State private var keyboardMonitor: Any? = nil
    // Set to true when ESC/⌘C trigger an async background save, so onDisappear skips the redundant sync save
    @State private var backgroundSaveInFlight = false

    // Crop tool
    @State private var cropRect: CGRect? = nil
    @State private var cropConfirmVisible = false

    // Eyedropper HUD
    @State private var eyedropperPickedHex: String? = nil

    // Sprint D — new tool states
    @State private var smartHighlightLineHeight: CGFloat = 28
    @State private var magnifierRadius: CGFloat = 50
    @State private var magnifierScale: CGFloat = 2.0
    @State private var showingResizeDialog = false
    @State private var resizeWidth: Double = 0
    @State private var resizeHeight: Double = 0
    @State private var resizeAspectLock = true

    private let toolBtn: CGFloat = 26
    private let toolbarH: CGFloat = 72   // two rows of 36
    private let footerH: CGFloat = 22
    private let minZoom: CGFloat = 0.1
    private let maxZoom: CGFloat = 10.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            toolOptionsPanel
            if backdrop.isActive {
                Divider()
                beautifyPanel
            }
            Divider()
            canvasArea
            footer
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear { installKeyboardMonitor(); installScrollMonitor() }
        .onDisappear {
            // Persist edits back to the source file on close.
            // Skip if ESC/⌘C already dispatched a background save for this session.
            if filePath != nil, hasEdits, !backgroundSaveInFlight { saveBackToFile() }
            if let mon = keyboardMonitor { NSEvent.removeMonitor(mon) }
            if let mon = scrollMonitor { NSEvent.removeMonitor(mon) }
            keyboardMonitor = nil
            scrollMonitor = nil
        }
    }

    /// Trackpad/mouse-wheel scrolling: pans the image when zoomed in, and
    /// ⌘-scroll zooms. Without this, panOffset never changed, so a zoomed-in
    /// image could not be navigated at all.
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard window.isKeyWindow else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if mods.contains(.command) {
                guard event.scrollingDeltaY != 0 else { return nil }
                let factor = 1 + (event.scrollingDeltaY * 0.005)
                zoomScale = min(maxZoom, max(minZoom, zoomScale * factor))
                lastZoom = zoomScale
                clampPan()
                return nil
            }

            // Pan only when zoomed in; otherwise let the event through so panels scroll.
            guard zoomScale > 1.0 else { return event }
            panOffset.width += event.scrollingDeltaX
            panOffset.height += event.scrollingDeltaY
            clampPan()
            return nil
        }
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
                // Crop overlay
                if currentTool == .crop, let cr = cropRect {
                    let (scale, offset) = computeTransform(geo: geo)
                    let viewCropRect = applyRect(cr, scale: scale, offset: offset)
                    ZStack {
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: geo.size))
                            p.addRect(viewCropRect)
                        }
                        .fill(Color.black.opacity(0.4), style: FillStyle(eoFill: true))
                        Rectangle()
                            .stroke(Color.white, lineWidth: 1.5)
                            .frame(width: viewCropRect.width, height: viewCropRect.height)
                            .position(x: viewCropRect.midX, y: viewCropRect.midY)
                    }
                    .allowsHitTesting(false)
                }
                // Eyedropper HUD
                if let hex = eyedropperPickedHex {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(currentColor)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                        Text(hex)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("copied")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.75))
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeOut(duration: 0.3), value: eyedropperPickedHex)
                }
                // Crop confirm bar
                if cropConfirmVisible, cropRect != nil {
                    HStack(spacing: 8) {
                        Button("Crop") {
                            applyCrop()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Button("Cancel") {
                            cropRect = nil
                            cropConfirmVisible = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 40)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .rotationEffect(.degrees(rotation))
            .padding(rotation != 0 ? 40 : 0)
            .gesture(canvasDragGesture(geo: geo))
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        // value.magnitude is cumulative (1.0 at start); anchor to the
                        // zoom captured when the pinch began so it doesn't compound.
                        zoomScale = min(maxZoom, max(minZoom, lastZoom * value.magnitude))
                    }
                    .onEnded { value in
                        lastZoom = min(maxZoom, max(minZoom, lastZoom * value.magnitude))
                        zoomScale = lastZoom
                    }
            )
            .onContinuousHover { phase in
                if case .moved(let pt) = phase { cursorLocation = pt }
            }
            .contextMenu {
                if selectedAnnotationId != nil {
                    Button("Delete", systemImage: "trash") { deleteSelected() }
                        .keyboardShortcut(.delete)
                    Divider()
                    Button("Bring to Front", systemImage: "arrow.up.to.line.compact") { bringToFront() }
                        .keyboardShortcut("]")
                    Button("Send to Back", systemImage: "arrow.down.to.line.compact") { sendToBack() }
                        .keyboardShortcut("[")
                    Button("Bring Forward", systemImage: "arrow.up") { bringForward() }
                    Button("Send Backward", systemImage: "arrow.down") { sendBackward() }
                    Divider()
                    Button("Duplicate", systemImage: "plus.square") { duplicateSelected() }
                } else {
                    Button("Paste from Clipboard", systemImage: "clipboard") { pasteImage() }
                }
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
        .sheet(isPresented: $showingResizeDialog) {
            resizeDialogView
        }
    }

    private var resizeDialogView: some View {
        VStack(spacing: 16) {
            Text("Resize Image").font(.headline)
            HStack {
                Text("Width:")
                TextField("", value: $resizeWidth, format: .number).frame(width: 80)
                Text("px")
            }
            HStack {
                Text("Height:")
                TextField("", value: $resizeHeight, format: .number).frame(width: 80)
                Text("px")
            }
            HStack {
                Toggle("Maintain aspect ratio", isOn: $resizeAspectLock)
                Spacer()
            }
            HStack {
                Button("Cancel", role: .cancel) {}
                Button("Resize") {
                    performImageResize()
                    showingResizeDialog = false
                }.buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 280)
    }

    private func performImageResize() {
        guard resizeWidth > 0, resizeHeight > 0 else { return }
        pushUndoImage()
        let newSize = NSSize(width: resizeWidth, height: resizeHeight)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        workingImage.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: workingImage.size), operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        workingImage = resized
    }

    private func performContrastCheck() {
        guard let cgImage = workingImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            ocrAlertMessage = "Could not get image data."
            return
        }
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return }
        // Simplified contrast estimation
        guard let provider = cgImage.dataProvider, let data = provider.data else { return }
        let ptr = CFDataGetBytePtr(data)!
        var totalLuma: Double = 0
        var pixels = 0
        for y in stride(from: 0, to: h, by: max(1, h/50)) {
            for x in stride(from: 0, to: w, by: max(1, w/50)) {
                let offset = (y * cgImage.bytesPerRow) + x * 4
                let r = Double(ptr[offset]) / 255.0
                let g = Double(ptr[offset + 1]) / 255.0
                let b = Double(ptr[offset + 2]) / 255.0
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                totalLuma += luma
                pixels += 1
            }
        }
        guard pixels > 0 else { return }
        let avgLuma = totalLuma / Double(pixels)
        let contrastRatio = abs(avgLuma - 0.5) * 2 + 0.5
        let rating: String
        if contrastRatio > 0.8 { rating = "Excellent" }
        else if contrastRatio > 0.6 { rating = "Good" }
        else if contrastRatio > 0.4 { rating = "Fair" }
        else { rating = "Poor" }
        ocrAlertMessage = "Average Contrast: \(String(format: "%.2f", contrastRatio))\nRating: \(rating)"
    }

    private func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
            case (8, _) where mods == [.command]: // ⌘C — save edits, copy, dismiss
                // Render once; use for both clipboard copy and background save.
                if let exported = exportImage() {
                    Clipboard.copy(image: exported)
                    if hasEdits, let path = filePath {
                        backgroundSaveInFlight = true
                        Self.backgroundWrite(exported, to: path)
                    }
                }
                window.performClose(nil)
                return nil
            case (1, _) where mods == [.command]: // ⌘S — save
                exportAndSave()
                return nil
            case (53, _): // Esc — render now (fast), close immediately, write in background (slow)
                if hasEdits, let path = filePath {
                    let exported = exportImage() ?? workingImage
                    backgroundSaveInFlight = true
                    window.performClose(nil)
                    Self.backgroundWrite(exported, to: path)
                } else {
                    window.performClose(nil)
                }
                return nil
            case (24, _) where mods == [.command]: // ⌘=
                zoomIn()
                return nil
            case (27, _) where mods == [.command]: // ⌘-
                zoomOut()
                return nil
            case (29, _) where mods == [.command]: // ⌘0
                resetZoom()
                return nil
            case (30, _) where mods == [.command]: // ⌘]
                bringForward()
                return nil
            case (33, _) where mods == [.command]: // ⌘[
                sendBackward()
                return nil
            default:
                break
            }
            // Don't activate tool shortcuts while the text input alert is visible.
            guard !showingTextAlert else { return event }

            // Tool shortcuts — look up from user-configurable prefs.
            // Keys stored as single chars ("l", "1") or "⇧" + char for shift variants.
            let bindings = AppStore.shared.preferences.editorHotkeys
            var charToTool: [String: DrawingTool] = [:]
            for (toolRaw, keyChar) in bindings {
                if let tool = DrawingTool(rawValue: toolRaw) {
                    charToTool[keyChar] = tool
                }
            }
            let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if mods == .shift, let tool = charToTool["⇧\(char)"] {
                currentTool = tool
                return nil
            }
            if mods.isEmpty, let tool = charToTool[char] {
                currentTool = tool
                return nil
            }
            return event
        }
    }

    // MARK: - Layers

    @ViewBuilder
    private func imageLayer(geo: GeometryProxy) -> some View {
        let (scale, offset) = computeTransform(geo: geo)
        let imgSize = workingImage.size
        let imageRect = CGRect(x: offset.width, y: offset.height,
                               width: imgSize.width * scale, height: imgSize.height * scale)

        if backdrop.isActive {
            let framed = backdropFramedRect(geo: geo)
            let radius = min(backdrop.cornerRadius * scale, min(framed.width, framed.height) / 2)
            let barH = backdrop.showWindowFrame ? BackdropMetrics.barHeight(width: imgSize.width) * scale : 0

            // Backdrop fills the exported card area.
            BackdropBackground(style: backdrop)
                .frame(width: framed.width, height: framed.height)
                .position(x: framed.midX, y: framed.midY)

            // Screenshot + optional window chrome, rounded + shadowed as one card.
            VStack(spacing: 0) {
                if backdrop.showWindowFrame {
                    WindowChromeBar(height: barH)
                }
                Image(nsImage: workingImage)
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: .black.opacity(backdrop.shadowOpacity),
                    radius: backdrop.shadowRadius * scale * 0.6,
                    y: backdrop.shadowRadius * scale * 0.25)
            .frame(width: imageRect.width, height: imageRect.height + barH)
            .position(x: imageRect.midX, y: imageRect.midY - barH / 2)
        } else {
            Image(nsImage: workingImage)
                .resizable()
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)
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
                    lineWidth: currentLineWidth,
                    lineStyle: currentLineStyle,
                    arrowHeadStyle: currentArrowHeadStyle
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

            // Draw main line with line style
            drawStyledLine(from: sa, to: ea, color: annotation.color, lineWidth: annotation.lineWidth, style: annotation.lineStyle, ctx: &ctx)

            // Draw arrow head based on style
            let angle = atan2(ea.y - sa.y, ea.x - sa.x)
            let headLen: CGFloat = 12
            drawArrowHead(at: ea, angle: angle, length: headLen, style: annotation.arrowHeadStyle, color: annotation.color, lineWidth: annotation.lineWidth, ctx: &ctx)
        case .line(let start, let end):
            let sl = cgApply(start, scale: scale, offset: offset)
            let el = cgApply(end, scale: scale, offset: offset)
            drawStyledLine(from: sl, to: el, color: annotation.color, lineWidth: annotation.lineWidth, style: annotation.lineStyle, ctx: &ctx)
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
        case .text(let pos, let text, let fontSize, let style):
            let p = cgApply(pos, scale: scale, offset: offset)
            var font: Font = .system(size: fontSize * scale)
            if style == .bold || style == .boldItalic {
                font = .system(size: fontSize * scale, weight: .semibold)
            }
            ctx.draw(Text(text).font(font).foregroundColor(annotation.color), at: p, anchor: .topLeading)
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
        case .freehandErase:
            break
        case .curvedArrow(let start, let control, let end):
            let sa = cgApply(start, scale: scale, offset: offset)
            let ca = cgApply(control, scale: scale, offset: offset)
            let ea = cgApply(end, scale: scale, offset: offset)
            var path = Path()
            path.move(to: sa)
            path.addQuadCurve(to: ea, control: ca)
            ctx.stroke(path, with: .color(annotation.color), lineWidth: annotation.lineWidth)
            let angle = atan2(ea.y - ca.y, ea.x - ca.x)
            let headLen: CGFloat = 12
            drawArrowHead(at: ea, angle: angle, length: headLen, style: annotation.arrowHeadStyle, color: annotation.color, lineWidth: annotation.lineWidth, ctx: &ctx)
        case .smartHighlight(let origin, let size):
            let r = CGRect(origin: origin, size: size).standardized
            let vr = applyRect(r, scale: scale, offset: offset)
            ctx.fill(Path(vr), with: .color(annotation.color.opacity(0.25)))
            ctx.stroke(Path(vr), with: .color(annotation.color.opacity(0.5)), lineWidth: 1)
            let midY = vr.midY
            var linePath = Path()
            linePath.move(to: CGPoint(x: vr.minX, y: midY))
            linePath.addLine(to: CGPoint(x: vr.maxX, y: midY))
            ctx.stroke(linePath, with: .color(annotation.color.opacity(0.8)), lineWidth: 2)
        case .magnifierCallout(let center, let calloutPoint, let radius, _):
            let cp = cgApply(center, scale: scale, offset: offset)
            let bp = cgApply(calloutPoint, scale: scale, offset: offset)
            let r = radius * scale

            var linePath = Path()
            linePath.move(to: cp)
            linePath.addLine(to: bp)
            ctx.stroke(linePath, with: .color(annotation.color.opacity(0.5)), lineWidth: annotation.lineWidth)

            ctx.fill(Path(ellipseIn: CGRect(x: cp.x - r, y: cp.y - r, width: r*2, height: r*2)), with: .color(.black.opacity(0.08)))
            ctx.stroke(Path(ellipseIn: CGRect(x: cp.x - r, y: cp.y - r, width: r*2, height: r*2)), with: .color(annotation.color), lineWidth: 2)
            ctx.draw(Text("\u{1F50D}").font(.system(size: r * 0.6)), at: cp, anchor: .center)

            let bubbleW: CGFloat = 100 * scale
            let bubbleH: CGFloat = 40 * scale
            let bubbleRect = CGRect(x: bp.x - bubbleW / 2, y: bp.y - bubbleH / 2, width: bubbleW, height: bubbleH)
            ctx.fill(Path(roundedRect: bubbleRect, cornerRadius: 8 * scale), with: .color(annotation.color.opacity(0.15)))
            ctx.stroke(Path(roundedRect: bubbleRect, cornerRadius: 8 * scale), with: .color(annotation.color), lineWidth: 1.5)
            ctx.draw(Text("\(Int((self.magnifierScale)))x").font(.system(size: 12 * scale, weight: .bold)).foregroundColor(annotation.color), at: bp, anchor: .center)
        }

        if highlight {
            // Resize handles at corners
            let handles = resizeHandles(for: annotation)
            for h in handles {
                let hp = cgApply(h, scale: scale, offset: offset)
                let dot = CGRect(origin: CGPoint(x: hp.x - 4, y: hp.y - 4), size: CGSize(width: 8, height: 8))
                ctx.fill(Path(ellipseIn: dot), with: .color(.white))
                ctx.stroke(Path(ellipseIn: dot), with: .color(.yellow.opacity(0.8)), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Coordinate helpers

    private func computeTransform(geo: GeometryProxy) -> (CGFloat, CGSize) {
        // Fit the screenshot — plus any backdrop padding/frame — into the canvas.
        // Using workingImage.size (not the original image.size) keeps annotations
        // aligned after a crop.
        let imgSize = workingImage.size
        let ins = backdropInsets()
        let boxW = imgSize.width + ins.left + ins.right
        let boxH = imgSize.height + ins.top + ins.bottom
        let baseScale = min(geo.size.width / boxW, geo.size.height / boxH)
        let scale = baseScale * zoomScale
        let boxOriginX = (geo.size.width - boxW * scale) / 2 + panOffset.width
        let boxOriginY = (geo.size.height - boxH * scale) / 2 + panOffset.height
        let offset = CGSize(
            width: boxOriginX + ins.left * scale,
            height: boxOriginY + ins.top * scale
        )
        return (scale, offset)
    }

    /// Backdrop insets around the screenshot, in image-space points.
    /// `.none` → zero insets, so the transform reduces to a plain centered fit.
    private func backdropInsets() -> NSEdgeInsets {
        guard backdrop.isActive else { return NSEdgeInsets() }
        let size = workingImage.size
        let pad = BackdropMetrics.padding(content: size, style: backdrop)
        let bar = backdrop.showWindowFrame ? BackdropMetrics.barHeight(width: size.width) : 0
        return NSEdgeInsets(top: pad + bar, left: pad, bottom: pad, right: pad)
    }

    /// The full backdrop "card+padding" rect in view space (what gets exported).
    private func backdropFramedRect(geo: GeometryProxy) -> CGRect {
        let (scale, offset) = computeTransform(geo: geo)
        let ins = backdropInsets()
        let imgSize = workingImage.size
        return CGRect(
            x: offset.width - ins.left * scale,
            y: offset.height - ins.top * scale,
            width: (imgSize.width + ins.left + ins.right) * scale,
            height: (imgSize.height + ins.top + ins.bottom) * scale
        )
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
        case .line: return .line(start: start, end: end)
        case .curvedArrow:
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let perpX = -dy * 0.3
            let perpY = dx * 0.3
            let control = CGPoint(x: mid.x + perpX, y: mid.y + perpY)
            return .curvedArrow(start: start, control: control, end: end)
        case .rect:  return .rect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .circle: return .circle(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .highlight, .smartHighlight: return .highlight(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .blur:  return .blur(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .mosaic: return .mosaic(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .spotlight: return .spotlight(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y))
        case .ruler: return .ruler(start: start, end: end)
        case .magnifierCallout: return .magnifierCallout(center: start, calloutPoint: end, radius: magnifierRadius, scale: magnifierScale)
        default: return .arrow(start: start, end: end)
        }
    }

    // MARK: - Gesture

    private func canvasDragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let pt = canvasPoint(from: value.location, geo: geo)

                if isResizingAnnotation, let start = dragStart, let orig = resizeStartAnnotation, let selId = selectedAnnotationId {
                    if let idx = annotations.firstIndex(where: { $0.id == selId }) {
                        let delta = CGSize(width: pt.x - start.x, height: pt.y - start.y)
                        annotations[idx] = resizedAnnotation(orig, handle: resizeHandleIndex, delta: delta)
                    }
                    return
                }

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

                // First move — check if we're on a resize handle or annotation
                if value.translation.width == 0 && value.translation.height == 0 {
                    if let selId = selectedAnnotationId,
                       let selAnn = annotations.first(where: { $0.id == selId }) {
                        if let handleIdx = hitTestResizeHandle(selAnn, point: pt) {
                            isResizingAnnotation = true
                            resizeHandleIndex = handleIdx
                            dragStart = pt
                            resizeStartAnnotation = selAnn
                            return
                        }
                        if selAnn.contains(point: pt) {
                            isMovingAnnotation = true
                            dragStart = pt
                            moveStartAnnotation = selAnn
                            return
                        }
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

                if currentTool == .eraser {
                    if !isDrawing {
                        isDrawing = true
                        dragStart = pt
                    }
                    eraserSwipePoints.append(pt)
                    let touchedIds = annotations.filter { $0.contains(point: pt) }.map(\.id)
                    if !touchedIds.isEmpty {
                        pushUndo()
                        annotations.removeAll { touchedIds.contains($0.id) }
                        selectedAnnotationId = nil
                    }
                    return
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
                case .eyedropper:
                    // No drag needed — handled in onEnded
                    break
                case .crop:
                    if !isDrawing {
                        dragStart = pt
                        isDrawing = true
                    }
                    dragCurrent = pt
                    if let s = dragStart {
                        cropRect = CGRect(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)).standardized
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
                    isResizingAnnotation = false
                    dragStart = nil
                    dragCurrent = nil
                    moveStartAnnotation = nil
                    resizeStartAnnotation = nil
                    freehandPoints = []
                    eraserSwipePoints = []
                }
                if isMovingAnnotation { pushUndo(); return }
                if isResizingAnnotation { pushUndo(); return }
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
                    annotations.append(Annotation(type: .arrow(start: s, end: pt), color: currentColor, fillColor: fc, lineWidth: currentLineWidth, lineStyle: currentLineStyle, arrowHeadStyle: currentArrowHeadStyle))
                case .line:
                    annotations.append(Annotation(type: .line(start: s, end: pt), color: currentColor, fillColor: fc, lineWidth: currentLineWidth, lineStyle: currentLineStyle))
                case .curvedArrow:
                    let mid = CGPoint(x: (s.x + pt.x) / 2, y: (s.y + pt.y) / 2)
                    let dx = pt.x - s.x
                    let dy = pt.y - s.y
                    let perpX = -dy * 0.3
                    let perpY = dx * 0.3
                    let control = CGPoint(x: mid.x + perpX, y: mid.y + perpY)
                    annotations.append(Annotation(type: .curvedArrow(start: s, control: control, end: pt), color: currentColor, fillColor: fc, lineWidth: currentLineWidth, lineStyle: currentLineStyle, arrowHeadStyle: currentArrowHeadStyle))
                case .rect:
                    annotations.append(Annotation(type: .rect(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .circle:
                    annotations.append(Annotation(type: .circle(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .highlight, .smartHighlight:
                    let r = CGRect(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)).standardized
                    guard r.width > 5 && r.height > 5 else { return }
                    if currentTool == .smartHighlight {
                        let snappedRect = CGRect(origin: CGPoint(x: r.origin.x, y: s.y), size: CGSize(width: r.width, height: smartHighlightLineHeight))
                        annotations.append(Annotation(type: .smartHighlight(origin: snappedRect.origin, size: snappedRect.size), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                    } else {
                        annotations.append(Annotation(type: .highlight(origin: r.origin, size: r.size), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                    }
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
                case .magnifierCallout:
                    let dist = hypot(pt.x - s.x, pt.y - s.y)
                    guard dist > 10 else { return }
                    annotations.append(Annotation(type: .magnifierCallout(center: s, calloutPoint: pt, radius: magnifierRadius, scale: magnifierScale), color: currentColor, fillColor: fc, lineWidth: currentLineWidth))
                case .eraser:
                    break
                case .eyedropper:
                    pickColor(at: pt)
                case .crop:
                    let r = CGRect(origin: s, size: CGSize(width: pt.x - s.x, height: pt.y - s.y)).standardized
                    if r.width > 5 && r.height > 5 {
                        cropRect = r
                        cropConfirmVisible = true
                    }
                }
            }
    }

    // MARK: - Eyedropper

    private func pickColor(at imagePoint: CGPoint) {
        guard let cgImage = workingImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        // cgImage dimensions are in physical pixels; workingImage.size is in points.
        // Account for Retina scale so we sample the correct pixel.
        let pointSize = workingImage.size
        let scaleX = CGFloat(cgImage.width) / pointSize.width
        let scaleY = CGFloat(cgImage.height) / pointSize.height
        let pxX = max(0, min(Int(imagePoint.x * scaleX), cgImage.width - 1))
        // Canvas y=0 is top; CGImage y=0 is bottom — flip and scale
        let pxY = max(0, min(Int((pointSize.height - imagePoint.y) * scaleY), cgImage.height - 1))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        ctx.draw(cgImage, in: CGRect(x: -CGFloat(pxX), y: -CGFloat(pxY),
                                     width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        let r = pixel[0], g = pixel[1], b = pixel[2]
        let hex = HexColor.string(r: Int(r), g: Int(g), b: Int(b))
        currentColor = Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
        Clipboard.copy(text: hex)
        eyedropperPickedHex = hex
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if eyedropperPickedHex == hex { eyedropperPickedHex = nil }
        }
    }

    // MARK: - Crop

    private func applyCrop() {
        guard let r = cropRect else { return }
        guard let cgImage = workingImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        // cgImage is in physical pixels; cropRect is in image-space points.
        // Scale to pixels and flip Y (canvas: y-down, CGImage: y-up).
        let pointSize = workingImage.size
        let scaleX = CGFloat(cgImage.width) / pointSize.width
        let scaleY = CGFloat(cgImage.height) / pointSize.height
        let pixelRect = CGRect(
            x: r.origin.x * scaleX,
            y: (pointSize.height - r.maxY) * scaleY,
            width: r.width * scaleX,
            height: r.height * scaleY
        ).intersection(CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        guard pixelRect.width > 0, pixelRect.height > 0 else { return }
        guard let cropped = cgImage.cropping(to: pixelRect) else { return }
        pushUndoImage()
        // NSImage size in points = pixel size / scale so the image renders at 1:1 on screen
        workingImage = NSImage(cgImage: cropped, size: NSSize(width: r.width, height: r.height))
        annotations.removeAll()
        cropRect = nil
        cropConfirmVisible = false
        resetZoom()
    }

    // MARK: - Resize & Layer Ordering

    private func hitTestResizeHandle(_ annotation: Annotation, point: CGPoint) -> Int? {
        let handles = resizeHandles(for: annotation)
        for (i, h) in handles.enumerated() {
            if CGRect(origin: CGPoint(x: h.x - 4, y: h.y - 4), size: CGSize(width: 8, height: 8)).contains(point) {
                return i
            }
        }
        return nil
    }

    private func resizeHandles(for annotation: Annotation) -> [CGPoint] {
        guard let r = annotationBoundingRect(annotation) else { return [] }
        return [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.maxX, y: r.maxY),
        ]
    }

    private func annotationBoundingRect(_ annotation: Annotation) -> CGRect? {
        switch annotation.type {
        case .rect(let o, let s), .circle(let o, let s), .blur(let o, let s),
             .highlight(let o, let s), .mosaic(let o, let s), .spotlight(let o, let s), .smartHighlight(let o, let s):
            return CGRect(origin: o, size: s).standardized
        case .arrow(let s, let e), .line(let s, let e):
            return CGRect(origin: s, size: CGSize(width: e.x - s.x, height: e.y - s.y)).standardized
        case .ruler(let s, let e):
            return CGRect(origin: s, size: CGSize(width: e.x - s.x, height: e.y - s.y)).standardized
        case .curvedArrow(let s, let control, let e):
            let xs = [s.x, control.x, e.x]; let ys = [s.y, control.y, e.y]
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!).standardized
        case .magnifierCallout(let center, let calloutPoint, let radius, _):
            let xs = [center.x - radius, center.x + radius, calloutPoint.x - 60, calloutPoint.x + 60]
            let ys = [center.y - radius, center.y + radius, calloutPoint.y - 30, calloutPoint.y + 30]
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!).standardized
        default:
            return nil
        }
    }

    private func resizedAnnotation(_ annotation: Annotation, handle: Int, delta: CGSize) -> Annotation {
        var copy = annotation
        switch annotation.type {
        case .rect(let o, let s), .circle(let o, let s), .blur(let o, let s),
             .highlight(let o, let s), .smartHighlight(let o, let s), .mosaic(let o, let s), .spotlight(let o, let s):
            var r = CGRect(origin: o, size: s)
            switch handle {
            case 0: r = CGRect(origin: CGPoint(x: r.minX + delta.width, y: r.minY + delta.height), size: CGSize(width: r.width - delta.width, height: r.height - delta.height))
            case 1: r = CGRect(origin: CGPoint(x: r.minX, y: r.minY + delta.height), size: CGSize(width: r.width + delta.width, height: r.height - delta.height))
            case 2: r = CGRect(origin: CGPoint(x: r.minX + delta.width, y: r.minY), size: CGSize(width: r.width - delta.width, height: r.height + delta.height))
            case 3: r = CGRect(origin: r.origin, size: CGSize(width: r.width + delta.width, height: r.height + delta.height))
            default: break
            }
            let std = r.standardized
            let newType: AnnotationType
            switch annotation.type {
            case .rect:      newType = .rect(origin: std.origin, size: std.size)
            case .circle:    newType = .circle(origin: std.origin, size: std.size)
            case .blur:      newType = .blur(origin: std.origin, size: std.size)
             case .highlight: newType = .highlight(origin: std.origin, size: std.size)
             case .smartHighlight: newType = .smartHighlight(origin: std.origin, size: std.size)
             case .mosaic:    newType = .mosaic(origin: std.origin, size: std.size)
            case .spotlight: newType = .spotlight(origin: std.origin, size: std.size)
            default: return annotation
            }
            copy.type = newType
        default:
            break
        }
        return copy
    }

    private func bringForward() {
        guard let id = selectedAnnotationId, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        guard idx < annotations.count - 1 else { return }
        pushUndo()
        annotations.swapAt(idx, idx + 1)
    }

    private func sendBackward() {
        guard let id = selectedAnnotationId, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        guard idx > 0 else { return }
        pushUndo()
        annotations.swapAt(idx, idx - 1)
    }

    private func bringToFront() {
        guard let id = selectedAnnotationId, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        annotations.append(annotations.remove(at: idx))
    }

    private func sendToBack() {
        guard let id = selectedAnnotationId, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        annotations.insert(annotations.remove(at: idx), at: 0)
    }

    private func duplicateSelected() {
        guard let id = selectedAnnotationId, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        var copy = annotations[idx]
        copy.id = UUID()
        annotations.insert(copy, at: idx + 1)
        selectedAnnotationId = copy.id
    }

    private func pasteImage() {
        guard let img = Clipboard.image() else { return }
        // Create a new editor window with the pasted image
        let editor = EditorWindow(image: img)
        editor.show()
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
        annotations.append(Annotation(type: .text(position: pendingTextPosition, text: textInput, fontSize: textFontSize, style: textStyle), color: currentColor, fillColor: nil, lineWidth: currentLineWidth))
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
        annotations.append(Annotation(type: .emoji(position: pendingEmojiPosition, text: emoji, fontSize: textFontSize), color: currentColor, fillColor: nil, lineWidth: currentLineWidth))
    }

    // MARK: - Zoom

    private func zoomIn() {
        zoomScale = min(maxZoom, zoomScale * 1.25)
        lastZoom = zoomScale
    }

    private func zoomOut() {
        zoomScale = max(minZoom, zoomScale / 1.25)
        lastZoom = zoomScale
        clampPan()
    }

    private func resetZoom() {
        zoomScale = 1.0
        lastZoom = 1.0
        panOffset = .zero
    }

    /// Keep the panned image from being dragged entirely off-screen.
    private func clampPan() {
        guard zoomScale > 1.0 else { panOffset = .zero; return }
        let limit = max(workingImage.size.width, workingImage.size.height) * zoomScale
        panOffset.width = min(max(panOffset.width, -limit), limit)
        panOffset.height = min(max(panOffset.height, -limit), limit)
    }

    private func rotate(_ degrees: CGFloat) {
        guard rotation != degrees else { return }
        pushUndo()
        rotation = degrees
    }

    // MARK: - Undo / Redo / Delete

    private func pushUndo() {
        canvasHistory.record(CanvasState(annotations: annotations, currentTool: currentTool, selectedAnnotationId: selectedAnnotationId, rotation: rotation))
    }

    private func pushUndoImage() {
        imageHistory.record(workingImage)
        pushUndo()
    }

    private func undo() {
        if let image = imageHistory.undo(current: workingImage) {
            workingImage = image
        }
        let current = CanvasState(annotations: annotations, currentTool: currentTool, selectedAnnotationId: selectedAnnotationId, rotation: rotation)
        guard let state = canvasHistory.undo(current: current) else { return }
        annotations = state.annotations
        currentTool = state.currentTool
        selectedAnnotationId = state.selectedAnnotationId
        rotation = state.rotation
    }

    private func redo() {
        if let image = imageHistory.redo(current: workingImage) {
            workingImage = image
        }
        let current = CanvasState(annotations: annotations, currentTool: currentTool, selectedAnnotationId: selectedAnnotationId, rotation: rotation)
        guard let state = canvasHistory.redo(current: current) else { return }
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

    // MARK: - Tool Options Panel

    private var toolOptionsPanel: some View {
        HStack(spacing: 8) {
            switch currentTool {
            case .arrow, .line, .curvedArrow:
                HStack(spacing: 6) {
                    Text("Line:")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Picker("", selection: $currentLineStyle) {
                        ForEach(LineStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 70)
                    .controlSize(.small)

                    if currentTool == .arrow || currentTool == .curvedArrow {
                        Divider().frame(height: 16)
                        Text("Head:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Picker("", selection: $currentArrowHeadStyle) {
                            ForEach(ArrowHeadStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                        .controlSize(.small)
                    }
                }
            case .text:
                HStack(spacing: 6) {
                    Text("Font:")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Picker("", selection: $textFontSize) {
                        ForEach([12, 16, 20, 24, 32, 48, 64], id: \.self) { size in
                            Text("\(size)").tag(CGFloat(size))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 50)
                    .controlSize(.small)

                    Divider()
                        .frame(height: 16)

                    // Bold button
                    Button {
                        textStyle = [.bold, .boldItalic].contains(textStyle) ?
                            ([.italic, .boldItalic].contains(textStyle) ? .italic : .regular) :
                            ([.italic, .boldItalic].contains(textStyle) ? .boldItalic : .bold)
                    } label: {
                        Text("B")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                            .background([.bold, .boldItalic].contains(textStyle) ? Color.accentColor : Color.secondary.opacity(0.1))
                            .foregroundColor([.bold, .boldItalic].contains(textStyle) ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .modernTooltip("Bold")

                    // Italic button
                    Button {
                        textStyle = [.italic, .boldItalic].contains(textStyle) ?
                            ([.bold, .boldItalic].contains(textStyle) ? .bold : .regular) :
                            ([.bold, .boldItalic].contains(textStyle) ? .boldItalic : .italic)
                    } label: {
                        Text("I")
                            .font(.system(size: 10, weight: .regular))
                            .italic()
                            .frame(width: 18, height: 18)
                            .background([.italic, .boldItalic].contains(textStyle) ? Color.accentColor : Color.secondary.opacity(0.1))
                            .foregroundColor([.italic, .boldItalic].contains(textStyle) ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .modernTooltip("Italic")
                }
            case .blur:
                HStack(spacing: 4) {
                    Text("Radius:")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Slider(value: $blurRadius, in: 4...32, step: 2)
                        .frame(width: 80)
                        .controlSize(.mini)
                    Text("\(Int(blurRadius))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                }
            case .stepNumber:
                HStack(spacing: 4) {
                    Button { stepCounter = max(1, stepCounter - 1) } label: {
                        Image(systemName: "minus").font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16, height: 16)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text("Start: \(stepCounter)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Button { stepCounter += 1 } label: {
                        Image(systemName: "plus").font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16, height: 16)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            default:
                EmptyView()
            }

            Spacer()

            if selectedAnnotationId != nil {
                layerOrderingButtons
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.04))
    }

    private var layerOrderingButtons: some View {
        HStack(spacing: 2) {
            Button { bringForward() } label: {
                Image(systemName: "arrow.up.to.line")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .help("Bring Forward (⌘])")

            Button { sendBackward() } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .help("Send Backward (⌘[)")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 0) {
            // ── Row 1: Drawing tools + fill + colors ──────────────────────────
            HStack(spacing: 0) {
                toolGroup([.rect, .circle, .arrow, .line])
                toolbarDivider
                toolGroup([.text, .stepNumber, .freehand])
                toolbarDivider
                toolGroup([.highlight, .blur, .mosaic])
                toolbarDivider
                toolGroup([.emoji, .eraser, .eyedropper, .crop])
                toolbarDivider
                fillToggle
                toolbarDivider
                colorStrip
                colorPickerButton
                Spacer(minLength: 0)
            }
            .frame(height: 36)

            Divider()

            // ── Row 2: Line width + zoom + rotate + actions ───────────────────
            HStack(spacing: 0) {
                lineWidthControl
                toolbarDivider
                zoomControls
                toolbarDivider
                rotateControls
                toolbarDivider
                Spacer(minLength: 0)
                actionButtons
            }
            .frame(height: 36)
        }
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial)
    }

    private func toolGroup(_ tools: [DrawingTool]) -> some View {
        HStack(spacing: 2) {
            ForEach(tools, id: \.self) { tool in
                toolButton(tool)
            }
        }
        .padding(.horizontal, 3)
    }

    private var toolbarDivider: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 2)
    }

    private func toolButton(_ tool: DrawingTool) -> some View {
        ToolButtonView(
            tool: tool,
            isSelected: currentTool == tool,
            icon: toolIcon(tool),
            tooltip: toolHelp(tool),
            onTap: { withAnimation(.easeOut(duration: 0.15)) { currentTool = tool } }
        )
    }


    private func toolHelp(_ tool: DrawingTool) -> String {
        let name = tool.rawValue.capitalized
        let shortcut = toolShortcut(tool).isEmpty ? "" : " (\(toolShortcut(tool)))"
        let desc: String
        switch tool {
        case .arrow:      desc = "Draw directional arrow"
        case .curvedArrow: desc = "Draw curved arrow"
        case .rect:       desc = "Draw rectangle"
        case .circle:     desc = "Draw circle / ellipse"
        case .text:       desc = "Add text label"
        case .blur:       desc = "Blur sensitive area"
        case .highlight:  desc = "Highlight region"
        case .smartHighlight: desc = "Smart line-aware highlight"
        case .freehand:   desc = "Freehand drawing"
        case .stepNumber: desc = "Numbered step marker"
        case .mosaic:     desc = "Pixelate area"
        case .emoji:      desc = "Insert emoji"
        case .ruler:      desc = "Measure distance"
        case .spotlight:  desc = "Spotlight highlight"
        case .magnifierCallout: desc = "Magnifier with callout"
        case .eraser:     desc = "Erase annotations"
        case .eyedropper: desc = "Sample color from image"
        case .crop:       desc = "Crop image to selection"
        case .line:       desc = "Draw a straight line"
        }
        return "\(name): \(desc)\(shortcut)"
    }

    private func toolIcon(_ tool: DrawingTool) -> String {
        switch tool {
        case .arrow:      return "arrow.up.right"
        case .curvedArrow: return "arrow.turn.down.right"
        case .line:       return "line.diagonal"
        case .rect:       return "square"
        case .circle:     return "circle"
        case .text:       return "textformat"
        case .blur:       return "circle.dotted"
        case .highlight:  return "highlighter"
        case .smartHighlight: return "line.horizontal.star.fill.line.horizontal"
        case .freehand:   return "pencil.tip"
        case .stepNumber: return "number"
        case .mosaic:     return "square.grid.3x3"
        case .emoji:      return "face.smiling"
        case .ruler:      return "ruler"
        case .spotlight:  return "circle.rectangle.dashed"
        case .magnifierCallout: return "magnifyingglass.circle"
        case .eraser:     return "eraser"
        case .eyedropper: return "eyedropper"
        case .crop:       return "crop"
        }
    }

    private func toolShortcut(_ tool: DrawingTool) -> String {
        AppStore.shared.preferences.editorHotkeys[tool.rawValue]?.uppercased() ?? ""
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
            // Recent colors (with divider if any exist)
            if !colorHistory.isEmpty {
                ForEach(colorHistory, id: \.self) { color in
                    colorSwatch(color)
                }
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 1, height: 12)
            }
            // Preset colors
            ForEach(editorColors, id: \.self) { color in
                colorSwatch(color)
            }
        }
        .padding(.horizontal, 6)
    }

    private func colorSwatch(_ color: Color) -> some View {
        Button {
            currentColor = color
            recordColorUsage(color)
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
        HexColor.string(from: color)
    }

    private var colorPickerButton: some View {
        ColorPicker("", selection: $currentColor, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 22, height: 22)
            .scaleEffect(0.7)
            .help("Pick custom color")
            .padding(.horizontal, 4)
            .onChange(of: currentColor) { _, newColor in
                recordColorUsage(newColor)
            }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Zoom Out (⌘-)")
            .handCursorOnHover()

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
            .handCursorOnHover()

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
            .handCursorOnHover()

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
            .handCursorOnHover()

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
            actionButton("arrow.uturn.backward", "Undo (⌘Z)", undo, canvasHistory.canUndo)
            actionButton("arrow.uturn.forward", "Redo (⇧⌘Z)", redo, canvasHistory.canRedo)
            actionButton("trash", "Delete (⌫)", deleteSelected, selectedAnnotationId != nil)
            toolbarDivider
            actionButton("doc.on.clipboard", "Copy (⌘C)", exportAndCopy, true)
            actionButton("text.viewfinder", "OCR — Copy text", performOCR, true)
            actionButton("qrcode.viewfinder", "QR — Scan & copy", performQRScan, true)
            actionButton("person.fill.viewfinder", "Remove Bg", performRemoveBackground, !removeBgRunning)
            actionButton("square.and.arrow.down", "Save (⌘S)", exportAndSave, true)
            let hasUploadURL = !AppStore.shared.preferences.uploadURL.isEmpty
            actionButton("icloud.and.arrow.up", uploading ? "Uploading…" : "Upload", uploadImage, hasUploadURL && !uploading)
            toolbarDivider
            actionButton("arrow.up.left.and.arrow.down.right", "Resize Image", { showingResizeDialog = true }, true)
            actionButton("circle.lefthalf.filled", "Contrast Checker", performContrastCheck, true)
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

    // MARK: - Color History

    private func recordColorUsage(_ color: Color) {
        colorHistory = RecentColors.recording(color, into: colorHistory)
    }

    // MARK: - Arrow Head Drawing

    private func drawArrowHead(at point: CGPoint, angle: CGFloat, length: CGFloat, style: ArrowHeadStyle, color: Color, lineWidth: CGFloat, ctx: inout GraphicsContext) {
        let headAngle: CGFloat = .pi / 7
        let p1 = CGPoint(x: point.x - length * cos(angle - headAngle), y: point.y - length * sin(angle - headAngle))
        let p2 = CGPoint(x: point.x - length * cos(angle + headAngle), y: point.y - length * sin(angle + headAngle))

        switch style {
        case .standard:
            // Two lines forming a V
            var arrow = Path()
            arrow.move(to: point)
            arrow.addLine(to: p1)
            arrow.move(to: point)
            arrow.addLine(to: p2)
            ctx.stroke(arrow, with: .color(color), lineWidth: lineWidth)

        case .filled:
            // Filled triangle
            var triangle = Path()
            triangle.move(to: point)
            triangle.addLine(to: p1)
            triangle.addLine(to: p2)
            triangle.closeSubpath()
            ctx.fill(triangle, with: .color(color))

        case .circle:
            // Circle at arrow tip
            let radius = length * 0.4
            ctx.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        }
    }

    // MARK: - Styled Line Drawing

    /// Efficiently draws a line with dashed/dotted style. O(n) complexity where n = distance.
    private func drawStyledLine(from: CGPoint, to: CGPoint, color: Color, lineWidth: CGFloat, style: LineStyle, ctx: inout GraphicsContext) {
        if style == .solid {
            // Fast path: solid lines use native rendering
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
            return
        }

        // Dashed/dotted: draw segments based on dash pattern
        let dashPattern = style.dashPattern
        let totalPattern = dashPattern.reduce(0, +)
        guard totalPattern > 0 else { return }

        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return }

        let unitX = dx / distance
        let unitY = dy / distance
        var currentDist: CGFloat = 0
        var patternIdx = 0
        var isDrawing = true

        while currentDist < distance {
            let segmentLen = dashPattern[patternIdx % dashPattern.count]
            let nextDist = min(currentDist + segmentLen, distance)
            let segmentLen_ = nextDist - currentDist

            if isDrawing && segmentLen_ > 0.5 {
                let startPt = CGPoint(x: from.x + unitX * currentDist, y: from.y + unitY * currentDist)
                let endPt = CGPoint(x: from.x + unitX * nextDist, y: from.y + unitY * nextDist)
                var segPath = Path()
                segPath.move(to: startPt)
                segPath.addLine(to: endPt)
                ctx.stroke(segPath, with: .color(color), lineWidth: lineWidth)
            }

            currentDist = nextDist
            patternIdx += 1
            isDrawing.toggle()
        }
    }

    // MARK: - Export

    private func exportAndCopy() {
        guard let exported = exportImage() else { return }
        Clipboard.copy(image: exported)
    }

    private func exportAndSave() {
        // If this image came from a capture/history file, save edits back to it
        // (overwrite) and refresh the history thumbnail — no Save panel needed.
        if filePath != nil {
            if saveBackToFile() {
                ToastWindow.show("Saved", icon: "checkmark.circle.fill", iconColor: .green)
            } else {
                ToastWindow.show("Couldn't save", icon: "exclamationmark.triangle.fill", iconColor: .orange)
            }
            return
        }
        guard let exported = exportImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Stag_\(Date().shotTimestamp).png"
        panel.beginSheetModal(for: window) { resp in
            guard resp == .OK, let url = panel.url else { return }
            exported.pngWrite(to: url)
        }
    }

    /// True when the user has made any change worth persisting.
    private var hasEdits: Bool {
        !annotations.isEmpty || rotation != 0 || backdrop.isActive || imageHistory.canUndo
    }

    /// Writes the edited image back to its source file synchronously (for ⌘S and safety-net onDisappear).
    @discardableResult
    private func saveBackToFile() -> Bool {
        guard let path = filePath else { return false }
        let exported = exportImage() ?? workingImage
        return Self.writeImageSync(exported, to: path)
    }

    /// Encodes and writes `image` to `path` on a background queue.
    /// History thumbnail is refreshed on the main queue when done.
    private static func backgroundWrite(_ image: NSImage, to path: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            writeImageSync(image, to: path)
        }
    }

    /// Encodes and writes synchronously; returns true on success.
    @discardableResult
    private static func writeImageSync(_ image: NSImage, to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let lower = path.lowercased()
        let data: Data?
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") {
            let props: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 0.9]
            data = image.tiffRepresentation
                .flatMap { NSBitmapImageRep(data: $0) }
                .flatMap { $0.representation(using: .jpeg, properties: props) }
        } else {
            data = image.pngData
        }
        guard let data else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return false
        }
        DispatchQueue.main.async {
            AppStore.shared.history.updateEditedImage(filePath: path, image: image)
        }
        return true
    }

    /// Final exported image: the flattened annotated screenshot, wrapped in the
    /// beautiful backdrop when one is active.
    private func exportImage() -> NSImage? {
        guard let annotated = flattenAnnotated() else { return nil }
        guard backdrop.isActive else { return annotated }
        return Backdrop.compose(content: annotated, style: backdrop)
    }

    /// Flattens the screenshot + annotations (with rotation) onto a transparent
    /// canvas. The backdrop is applied separately by `exportImage()`.
    private func flattenAnnotated() -> NSImage? {
        let imgSize = workingImage.size
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

        // Transparent base — the backdrop (if any) is composited later.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        ctx.fill(CGRect(origin: .zero, size: imgSize))
        workingImage.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)

        // The lockFocus context is y-up (origin bottom-left) but annotations are
        // stored in SwiftUI y-down coords. Flip each annotation's geometry so it
        // lands at the same place it was drawn on screen. (blur/mosaic already
        // flip internally, so they receive the raw y-down rect.)
        let H = imgSize.height
        func fp(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: H - p.y) }
        func fr(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }

        for annotation in annotations {
            // SwiftUI Color.cgColor is nil for standard colors (.red etc.) — use
            // NSColor(_:).cgColor which converts reliably.
            ctx.setStrokeColor(NSColor(annotation.color).cgColor)
            ctx.setLineWidth(annotation.lineWidth)

            switch annotation.type {
            case .arrow(let start, let end):
                drawArrow(on: ctx, from: fp(start), to: fp(end), annotation: annotation)
            case .line(let start, let end):
                ctx.move(to: fp(start))
                ctx.addLine(to: fp(end))
                ctx.strokePath()
            case .rect(let origin, let size):
                let rr = fr(CGRect(origin: origin, size: size).standardized)
                if let fc = annotation.fillColor {
                    ctx.setFillColor(NSColor(fc).cgColor)
                    ctx.fill(rr)
                }
                ctx.stroke(rr)
            case .circle(let origin, let size):
                let ce = fr(CGRect(origin: origin, size: size).standardized)
                if let fc = annotation.fillColor {
                    ctx.setFillColor(NSColor(fc).cgColor)
                    ctx.fillEllipse(in: ce)
                }
                ctx.strokeEllipse(in: ce)
            case .text(let pos, let text, let fontSize, let style):
                let font = (style == .bold || style == .boldItalic)
                    ? NSFont.boldSystemFont(ofSize: fontSize)
                    : NSFont.systemFont(ofSize: fontSize)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(annotation.color)
                ]
                // In y-up, draw point is the text's lower-left — offset by line height
                // so the on-screen top-left position is preserved.
                let th = (text as NSString).size(withAttributes: attrs).height
                text.draw(at: CGPoint(x: pos.x, y: H - pos.y - th), withAttributes: attrs)
            case .blur(let origin, let size):
                applyRealBlur(on: ctx, rect: CGRect(origin: origin, size: size).standardized, imageSize: imgSize)
            case .highlight(let origin, let size):
                if let color = NSColor(annotation.color).cgColor.copy(alpha: 0.3) {
                    ctx.setFillColor(color)
                    ctx.fill(fr(CGRect(origin: origin, size: size).standardized))
                }
            case .freehand(let points):
                guard points.count > 1 else { break }
                ctx.move(to: fp(points[0]))
                for pt in points.dropFirst() { ctx.addLine(to: fp(pt)) }
                ctx.strokePath()
            case .stepNumber(let center, let number):
                let c = fp(center)
                let r = CGRect(origin: c, size: .zero).insetBy(dx: -16, dy: -16)
                ctx.setFillColor(NSColor(annotation.color).cgColor)
                ctx.fillEllipse(in: r)
                let text = "\(number)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let textSize = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: c.x - textSize.width / 2, y: c.y - textSize.height / 2), withAttributes: attrs)
            case .mosaic(let origin, let size):
                applyRealMosaic(on: ctx, rect: CGRect(origin: origin, size: size).standardized, imageSize: imgSize)
            case .emoji(let pos, let emojiChar, let fontSize):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor(annotation.color)
                ]
                let textSize = emojiChar.size(withAttributes: attrs)
                let c = fp(pos)
                emojiChar.draw(at: CGPoint(x: c.x - textSize.width / 2, y: c.y - textSize.height / 2), withAttributes: attrs)
            case .ruler(let start, let end):
                drawRuler(on: ctx, from: fp(start), to: fp(end), annotation: annotation)
            case .spotlight(let origin, let size):
                applySpotlight(on: ctx, rect: CGRect(origin: origin, size: size).standardized, imageSize: imgSize)
            case .curvedArrow(let start, let control, let end):
                let s = fp(start), control2 = fp(control), e = fp(end)
                let path = CGMutablePath()
                path.move(to: s)
                let cp1 = CGPoint(x: s.x + (control2.x - s.x) * 0.5, y: s.y + (control2.y - s.y) * 0.3)
                let cp2 = control2
                path.addCurve(to: e, control1: cp1, control2: cp2)
                let arrowSize: CGFloat = 12 * annotation.lineWidth
                let angle = atan2(e.y - control2.y, e.x - control2.x)
                let ap1 = CGPoint(x: e.x - arrowSize * cos(angle - .pi / 6), y: e.y - arrowSize * sin(angle - .pi / 6))
                let ap2 = CGPoint(x: e.x - arrowSize * cos(angle + .pi / 6), y: e.y - arrowSize * sin(angle + .pi / 6))
                path.addLine(to: ap1); path.move(to: e); path.addLine(to: ap2)
                ctx.addPath(path)
                ctx.strokePath()
            case .smartHighlight(let origin, let size):
                let r = fr(CGRect(origin: origin, size: size).standardized)
                if let fillColor = NSColor(annotation.color).cgColor.copy(alpha: 0.3) {
                    ctx.setFillColor(fillColor)
                    ctx.fill(r)
                }
                ctx.setStrokeColor(NSColor(annotation.color).cgColor)
                ctx.setLineWidth(2)
                // underline along the on-screen bottom edge (now r.minY in y-up)
                ctx.strokeLineSegments(between: [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)])
            case .magnifierCallout(let center, let calloutPoint, let radius, let magScale):
                let c = fp(center), cp = fp(calloutPoint)
                let r = radius
                ctx.setStrokeColor(NSColor(annotation.color).cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2))
                ctx.strokeLineSegments(between: [c, cp])
                let bubbleRect = CGRect(x: cp.x - 50, y: cp.y - 15, width: 100, height: 30)
                if let bubbleColor = NSColor(annotation.color).cgColor.copy(alpha: 0.2) {
                    ctx.setFillColor(bubbleColor)
                    ctx.fill(bubbleRect)
                }
                let text = "\(Int(magScale))x" as NSString
                text.draw(at: CGPoint(x: cp.x - 25, y: cp.y - 10), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(annotation.color)])
            case .freehandErase:
                break
            }
        }
        result.unlockFocus()
        return result
    }

    private func performRemoveBackground() {
        removeBgRunning = true
        Task { @MainActor in
            defer { removeBgRunning = false }
            guard let cgImage = workingImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .balanced
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            do {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])
                guard let mask = request.results?.first as? VNPixelBufferObservation else {
                    ocrAlertMessage = "No person detected in this image."
                    return
                }
                let ciImage = CIImage(cvPixelBuffer: mask.pixelBuffer)
                let bgImage = CIImage(cgImage: cgImage)
                let maskImage = ciImage
                let filter = CIFilter(name: "CIBlendWithMask")!
                filter.setValue(bgImage, forKey: kCIInputImageKey)
                filter.setValue(CIImage(color: CIColor(red: 1, green: 1, blue: 1)), forKey: kCIInputBackgroundImageKey)
                filter.setValue(maskImage, forKey: kCIInputMaskImageKey)
                guard let output = filter.outputImage else { return }
                let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
                if let result = context.createCGImage(output, from: bgImage.extent) {
                    let nsImage = NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height))
                    pushUndoImage()
                    workingImage = nsImage
                    annotations.removeAll()
                    resetZoom()
                }
            } catch {
                ocrAlertMessage = "Remove background failed: \(error.localizedDescription)"
            }
        }
    }

    private func compositeOnBackground(cgImage: CGImage) -> CGImage? {
        let w = cgImage.width
        let h = cgImage.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private func performOCR() {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let request = VNRecognizeTextRequest { request, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.ocrAlertMessage = "OCR failed: \(error.localizedDescription)"
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation])?.compactMap { obs in
                    obs.topCandidates(1).first?.string
                } ?? []
                switch TextRecognition.ocrOutcome(from: lines) {
                case .noText:
                    self.ocrAlertMessage = "No text found in image."
                case .copied(let text, let lineCount):
                    Clipboard.copy(text: text)
                    self.ocrAlertMessage = "Copied \(lineCount) line(s) to clipboard."
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    private func performQRScan() {
        guard let cgImage = workingImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let request = VNDetectBarcodesRequest { req, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.ocrAlertMessage = "QR scan failed: \(error.localizedDescription)"
                    return
                }
                let payloads = (req.results as? [VNBarcodeObservation])?
                    .compactMap { $0.payloadStringValue } ?? []
                switch TextRecognition.barcodeOutcome(from: payloads) {
                case .none:
                    self.ocrAlertMessage = "No QR code or barcode found."
                case .found(let text, let count, let url, let firstPayload):
                    Clipboard.copy(text: text)
                    // If it looks like a URL, offer to open it
                    if let url = url {
                        let alert = NSAlert()
                        alert.messageText = "QR Code Found"
                        alert.informativeText = firstPayload
                        alert.addButton(withTitle: "Open URL")
                        alert.addButton(withTitle: "Copied — Done")
                        if alert.runModal() == .alertFirstButtonReturn {
                            NSWorkspace.shared.open(url)
                        }
                    } else {
                        self.ocrAlertMessage = "Copied \(count) code(s) to clipboard."
                    }
                }
            }
        }
        request.symbologies = [.qr, .aztec, .dataMatrix, .pdf417, .code128, .code39, .ean13, .ean8, .upce]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    private func uploadImage() {
        guard let exported = exportImage(), let png = exported.pngData else { return }
        let config = AppStore.shared.preferences.uploadConfig
        guard config.isConfigured else {
            ToastWindow.show("No upload endpoint set", icon: "exclamationmark.triangle", iconColor: .orange)
            return
        }
        uploading = true
        Task {
            do {
                let link = try await ImageUploader.upload(png, config: config)
                await MainActor.run {
                    self.uploading = false
                    Clipboard.copy(text: link)
                    ToastWindow.show("Link copied to clipboard", icon: "link", iconColor: .green)
                }
            } catch {
                await MainActor.run {
                    self.uploading = false
                    ToastWindow.show(error.localizedDescription, icon: "xmark.octagon", iconColor: .red)
                }
            }
        }
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
        guard let cgImage = workingImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
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
        guard let cgImage = workingImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
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
            Label("\(Int(workingImage.size.width)) × \(Int(workingImage.size.height))", systemImage: "rectangle.dashed")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            Label("\(Int(cursorLocation.x)), \(Int(cursorLocation.y))", systemImage: "cursor.rays")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            Text(toolDescription)
                .font(.system(size: 9))
                .foregroundColor(Color.secondary)
                .lineLimit(1)
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

    private var toolDescription: String {
        switch currentTool {
        case .arrow:           return "Click and drag to draw an arrow"
        case .curvedArrow:     return "Click and drag to draw a curved arrow"
        case .rect:            return "Click and drag to draw a rectangle"
        case .circle:          return "Click and drag to draw an ellipse"
        case .text:            return "Click to place a text label"
        case .blur:            return "Click and drag to blur an area"
        case .highlight:       return "Click and drag to highlight"
        case .smartHighlight:  return "Click and drag to highlight on a line"
        case .freehand:        return "Drag to draw freehand"
        case .stepNumber:      return "Click to place a numbered step"
        case .mosaic:          return "Click and drag to pixelate"
        case .emoji:           return "Click to choose and place an emoji"
        case .ruler:           return "Drag to measure distance"
        case .spotlight:       return "Drag to create a spotlight area"
        case .magnifierCallout: return "Click to place magnifier, drag to position callout"
        case .eraser:          return "Click or drag over annotations to erase them"
        case .eyedropper:      return "Click any pixel to sample its color — hex copied to clipboard"
        case .crop:            return "Drag to select crop region, then confirm to apply"
        case .line:            return "Click and drag to draw a straight line"
        }
    }

    // MARK: - Beautify panel

    private var beautifyPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                // Backdrop kind
                Picker("", selection: $backdrop.kind) {
                    ForEach(BackdropKind.allCases, id: \.self) { k in
                        Text(k.displayName).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 230)

                Divider().frame(height: 18)

                // Kind-specific source picker
                switch backdrop.kind {
                case .solid:
                    ColorPicker("", selection: $backdrop.solidColor, supportsOpacity: false)
                        .labelsHidden().frame(width: 32)
                case .gradient:
                    gradientSwatches
                case .image:
                    HStack(spacing: 6) {
                        Button("Desktop") { backdrop.wallpaper = desktopWallpaper() }
                            .controlSize(.small)
                        Button("Choose…") { importWallpaper() }
                            .controlSize(.small)
                    }
                case .none:
                    EmptyView()
                }

                Divider().frame(height: 18)

                sliderControl("Padding", value: $backdrop.paddingFraction, range: 0...0.25)
                sliderControl("Corners", value: $backdrop.cornerRadius, range: 0...48)
                sliderControl("Shadow", value: $backdrop.shadowRadius, range: 0...60)

                Toggle(isOn: $backdrop.showWindowFrame) {
                    Image(systemName: "macwindow")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Window frame")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
        }
        .background(Color.secondary.opacity(0.04))
    }

    private var gradientSwatches: some View {
        HStack(spacing: 5) {
            ForEach(Array(BackdropStyle.gradients.enumerated()), id: \.offset) { idx, preset in
                Button {
                    backdrop.gradientIndex = idx
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(preset.swiftUIGradient)
                        .frame(width: 22, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(backdrop.gradientIndex == idx ? Color.accentColor : Color.secondary.opacity(0.25),
                                        lineWidth: backdrop.gradientIndex == idx ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
    }

    private func sliderControl(_ label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            Slider(value: value, in: range).frame(width: 70).controlSize(.mini)
        }
    }

    private func desktopWallpaper() -> NSImage? {
        guard let screen = window.screen ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func importWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { resp in
            guard resp == .OK, let url = panel.url else { return }
            backdrop.wallpaper = NSImage(contentsOf: url)
        }
    }

    private var backdropControl: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                backdrop.kind = backdrop.isActive ? .none : .gradient
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("Beautify")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(backdrop.isActive ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backdrop.isActive ? Color.accentColor : Color.secondary.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(backdrop.isActive ? "Turn off backdrop" : "Add a beautiful backdrop")
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

// MARK: - Tool Button

private struct ToolButtonView: View {
    let tool: DrawingTool
    let isSelected: Bool
    let icon: String
    let tooltip: String
    let onTap: () -> Void
    @State private var isHovering = false
    private let size: CGFloat = 28

    var body: some View {
        Button(action: onTap) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : (isHovering ? .primary : .secondary))
                .frame(width: size, height: size)
                .background {
                    if isSelected {
                        Capsule().fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 4, y: 1)
                    } else if isHovering {
                        Capsule().fill(Color.secondary.opacity(0.15))
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { h in
            isHovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .modernTooltip(tooltip)
    }
}

// MARK: - Tooltip and Cursor Helpers

private struct TooltipModifier: ViewModifier {
    let text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .overlay(alignment: .top) {
                if isHovering {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.82))
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        )
                        .fixedSize()
                        .offset(y: -30)
                        .allowsHitTesting(false)
                        .transition(.opacity.animation(.easeInOut(duration: 0.1)))
                        .zIndex(999)
                }
            }
    }
}

extension View {
    /// Fast styled tooltip — shows immediately on hover (no macOS delay)
    func modernTooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }

    /// Hand pointer cursor on hover
    func handCursorOnHover() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.set() }
            else        { NSCursor.arrow.set() }
        }
    }
}
