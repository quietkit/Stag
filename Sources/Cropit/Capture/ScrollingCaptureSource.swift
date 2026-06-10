import Cocoa
import ScreenCaptureKit

@MainActor
final class ScrollingCaptureSource: CaptureSource {
    nonisolated let type: CaptureType = .scrolling
    private var overlayWindow: ScrollingWindowPicker?
    private var capturedWindowID: CGWindowID = 0

    func beginCapture(store: AppStore) async throws -> CaptureOutput {
        let image: CGImage = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let overlay = ScrollingWindowPicker()
                overlay.onWindowSelected = { [weak self] windowID in
                    overlay.close()
                    self?.overlayWindow = nil
                    Task {
                        do {
                            let img = try await self?.performScrollingCapture(windowID: windowID)
                            if let img {
                                continuation.resume(returning: img)
                            } else {
                                continuation.resume(throwing: CaptureError.captureFailed(reason: "Failed to capture scrolling window"))
                            }
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                overlay.onCancel = {
                    overlay.close()
                    continuation.resume(throwing: CaptureError.noActiveCapture)
                }
                overlay.show()
                self.overlayWindow = overlay
            }
        }
        return .image(image)
    }

    private func performScrollingCapture(windowID: CGWindowID) async throws -> CGImage {
        capturedWindowID = windowID

        // Get window info for dimensions
        guard let windowInfo = findWindowInfo(windowID: windowID) else {
            throw CaptureError.captureFailed(reason: "Window not found")
        }
        let windowRect = windowInfo.rect
        let windowPID = windowInfo.pid

        // First capture
        let firstImage = try await captureWindowImage(windowID: windowID)
        var frames: [(image: CGImage, rect: CGRect)] = [(firstImage, windowRect)]

        // Scroll the window down a page at a time, capturing as we go.
        let visibleHeight = windowRect.height
        let pageScroll = max(40, Int(visibleHeight * 0.85))   // overlap so stitching can align
        var scrollAttempts = 0
        let maxScrollAttempts = 40
        var lastImage = firstImage
        var hasMoreContent = true

        while hasMoreContent && scrollAttempts < maxScrollAttempts {
            scrollAttempts += 1

            scrollWindow(pid: windowPID, pixels: pageScroll)
            try await Task.sleep(nanoseconds: 350_000_000)

            let newImage = try await captureWindowImage(windowID: windowID)

            // If the frame is identical to the previous one, we've hit the bottom.
            if imagesEqual(newImage, lastImage) {
                hasMoreContent = false
                break
            }

            frames.append((newImage, windowRect))
            lastImage = newImage
        }

        // Scroll back to the top so we leave the window as we found it.
        for _ in 0..<scrollAttempts {
            scrollWindow(pid: windowPID, pixels: -pageScroll)
        }

        return try stitchWithOverlap(frames.map { $0.image })
    }

    private func imagesEqual(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              let da = a.dataProvider?.data, let db = b.dataProvider?.data,
              CFDataGetLength(da) == CFDataGetLength(db) else { return false }
        return memcmp(CFDataGetBytePtr(da), CFDataGetBytePtr(db), CFDataGetLength(da)) == 0
    }

    private struct WindowInfo {
        let rect: CGRect
        let pid: pid_t
    }

    private func findWindowInfo(windowID: CGWindowID) -> WindowInfo? {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for entry in list {
            guard let wid = entry[kCGWindowNumber as String] as? Int, wid == windowID else { continue }
            guard let dict = entry[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(
                x: dict["X"] ?? 0, y: dict["Y"] ?? 0,
                width: dict["Width"] ?? 0, height: dict["Height"] ?? 0
            )
            let pid = entry[kCGWindowOwnerPID as String] as? pid_t ?? 0
            return WindowInfo(rect: rect, pid: pid)
        }
        return nil
    }

    private func scrollWindow(pid: pid_t, pixels: Int) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: .activateIgnoringOtherApps)
        // Pixel units give a predictable, overlap-friendly scroll distance.
        // Negative wheel1 advances content downward (page-down).
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                            wheelCount: 1, wheel1: Int32(-pixels), wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    private func captureWindowImage(windowID: CGWindowID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scWindow = content.windows.first(where: { $0.windowID == windowID })
        else { throw CaptureError.captureFailed(reason: "Window not found") }

        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: - Overlap-aware stitching

    /// Stitches scroll frames by detecting how many pixels actually scrolled
    /// between consecutive frames and appending only the *new* rows. Naive
    /// concatenation duplicated the overlapping content into a giant garbled image.
    private func stitchWithOverlap(_ images: [CGImage]) throws -> CGImage {
        guard let first = images.first else {
            throw CaptureError.captureFailed(reason: "No frames captured")
        }
        let width = first.width
        let maxOutputHeight = 30_000   // safety cap

        // Each piece = a sub-rect (top-down y) of a source image to append.
        var pieces: [(img: CGImage, srcY: Int, height: Int)] = [(first, 0, first.height)]
        var totalHeight = first.height
        var prevHashes = rowHashes(first)

        for img in images.dropFirst() {
            guard img.width == width else { continue }
            let curHashes = rowHashes(img)
            let newRows = newContentRows(prev: prevHashes, cur: curHashes)
            prevHashes = curHashes
            // newRows <= 0 means we couldn't detect forward scroll — stop rather
            // than risk duplicating a full frame.
            guard newRows > 2 else { break }
            let h = min(newRows, img.height)
            pieces.append((img, img.height - h, h))
            totalHeight += h
            if totalHeight >= maxOutputHeight { break }
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: totalHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw CaptureError.captureFailed(reason: "Failed to create stitching context")
        }

        var yTop = 0
        for p in pieces {
            let region = CGRect(x: 0, y: p.srcY, width: width, height: p.height)
            guard let crop = p.img.cropping(to: region) else { continue }
            // CGContext is bottom-up; place this piece at output row `yTop`.
            let drawY = totalHeight - yTop - p.height
            ctx.draw(crop, in: CGRect(x: 0, y: drawY, width: width, height: p.height))
            yTop += p.height
        }

        guard let result = ctx.makeImage() else {
            throw CaptureError.captureFailed(reason: "Failed to stitch images")
        }
        return result
    }

    /// Per-row signature (top-to-bottom) sampled across columns, for alignment.
    private func rowHashes(_ image: CGImage) -> [UInt64] {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return [] }
        let bytesPerRow = w * 4
        var buf = [UInt8](repeating: 0, count: bytesPerRow * h)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = buf.withUnsafeMutableBytes({ ptr in
            CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let stride = max(1, w / 48) * 4   // sample ~48 columns
        var hashes = [UInt64](repeating: 0, count: h)
        for row in 0..<h {
            var hsh: UInt64 = 1469598103934665603
            let base = row * bytesPerRow
            var x = 0
            while x < bytesPerRow {
                let lum = UInt64(buf[base + x]) &+ UInt64(buf[base + x + 1]) &+ UInt64(buf[base + x + 2])
                hsh = (hsh ^ (lum >> 2)) &* 1099511628211
                x += stride
            }
            // Buffer is bottom-up; convert to top-down index.
            hashes[h - 1 - row] = hsh
        }
        return hashes
    }

    /// Number of new rows at the bottom of `cur` versus `prev` (the scroll delta).
    /// Returns 0 if no confident forward overlap is found.
    private func newContentRows(prev: [UInt64], cur: [UInt64]) -> Int {
        let h = min(prev.count, cur.count)
        guard h > 16 else { return 0 }
        let minRun = max(12, h / 5)
        var bestD = 0
        var bestScore = 0
        for d in 1..<h {
            let n = h - d
            var score = 0
            var y = 0
            while y < n {
                if cur[y] == prev[y + d] { score += 1 }
                y += 1
            }
            if score > bestScore { bestScore = score; bestD = d }
        }
        return bestScore >= minRun ? bestD : 0
    }
}

// MARK: - Window Picker Overlay

final class ScrollingWindowPicker: NSWindow {
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onCancel: (() -> Void)?

    private let pickerView: ScrollingPickerContentView

    init() {
        let totalFrame = NSScreen.screens.reduce(NSZeroRect) { $0.union($1.frame) }
        pickerView = ScrollingPickerContentView()

        super.init(contentRect: totalFrame, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        pickerView.frame = NSRect(origin: .zero, size: totalFrame.size)
        pickerView.autoresizingMask = [.width, .height]
        contentView = pickerView
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pickerView.windowRef = self
    }

    override func mouseDown(with event: NSEvent) {
        guard let windowID = pickerView.highlightedWindowID else { return }
        onWindowSelected?(windowID)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }

    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

final class ScrollingPickerContentView: NSView {
    var highlightedWindowID: CGWindowID?
    weak var windowRef: NSWindow?

    private var highlightedWindowRect: NSRect?
    private var highlightedWindowName: String?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let viewPoint = event.locationInWindow
        screenPoint = convertToScreenCoords(viewPoint)
        findWindow()
    }

    private var screenPoint: NSPoint = .zero

    private func convertToScreenCoords(_ viewPoint: NSPoint) -> NSPoint {
        guard let w = windowRef ?? window else { return viewPoint }
        let frame = w.frame
        if isFlipped {
            return NSPoint(x: viewPoint.x + frame.origin.x,
                           y: frame.origin.y + frame.height - viewPoint.y)
        }
        return NSPoint(x: viewPoint.x + frame.origin.x,
                       y: viewPoint.y + frame.origin.y)
    }

    private func findWindow() {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return }

        let ourWinNum = window?.windowNumber

        for info in list {
            guard let wid = info[kCGWindowNumber as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  wid != ourWinNum, layer == 0
            else { continue }

            let bounds = CGRect(
                x: dict["X"] ?? 0, y: dict["Y"] ?? 0,
                width: dict["Width"] ?? 0, height: dict["Height"] ?? 0
            )

            guard bounds.contains(screenPoint) else { continue }

            let name = info[kCGWindowOwnerName as String] as? String ?? ""
            let skipNames: Set<String> = ["Dock", "Window Server", "", "SystemUIServer", "ControlCenter"]
            guard !skipNames.contains(name) else { continue }

            if highlightedWindowID != CGWindowID(wid) {
                highlightedWindowID = CGWindowID(wid)
                highlightedWindowRect = bounds
                highlightedWindowName = name
                needsDisplay = true
            }
            return
        }

        if highlightedWindowID != nil {
            highlightedWindowID = nil
            highlightedWindowRect = nil
            highlightedWindowName = nil
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let w = windowRef ?? window
        else { return }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.12))
        ctx.fill(dirtyRect)

        guard let rect = highlightedWindowRect, let name = highlightedWindowName else { return }

        let viewRect = screenRectToView(rect, window: w)

        ctx.setStrokeColor(CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.9))
        ctx.setLineWidth(3)
        ctx.setShadow(offset: .zero, blur: 6, color: CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.4))
        ctx.stroke(viewRect)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        let handleSize: CGFloat = 8
        let half = handleSize / 2
        ctx.setFillColor(CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1))
        for corner in cornerPoints(rect: viewRect) {
            ctx.fillEllipse(in: CGRect(x: corner.x - half, y: corner.y - half, width: handleSize, height: handleSize))
        }

        let badgeText = "⇟ Scrolling" as NSString
        let badgeSize = badgeText.size(withAttributes: badgeAttrs)
        let badgeRect = NSRect(
            x: viewRect.midX - badgeSize.width / 2 - 6,
            y: viewRect.maxY + 8,
            width: badgeSize.width + 12,
            height: 22
        )
        let bgPath = CGPath(roundedRect: badgeRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(bgPath)
        ctx.setFillColor(CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.85))
        ctx.fillPath()
        badgeText.draw(at: NSPoint(x: badgeRect.minX + 6, y: badgeRect.minY + 4),
                       withAttributes: badgeAttrs)

        let label = name as NSString
        let labelSize = label.size(withAttributes: labelAttrs)
        let labelW = min(labelSize.width + 12, viewRect.width + 20)
        let labelRect = NSRect(
            x: viewRect.midX - labelW / 2,
            y: viewRect.minY - 28,
            width: labelW,
            height: 22
        )
        let labelBg = CGPath(roundedRect: labelRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(labelBg)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.75))
        ctx.fillPath()
        label.draw(at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 4),
                   withAttributes: labelAttrs)
    }

    private let badgeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.white
    ]

    private let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white
    ]

    private func screenRectToView(_ screenRect: NSRect, window: NSWindow) -> NSRect {
        let frame = window.frame
        if isFlipped {
            return NSRect(
                x: screenRect.minX - frame.minX,
                y: frame.height - screenRect.maxY + frame.minY,
                width: screenRect.width,
                height: screenRect.height
            )
        }
        return NSRect(
            x: screenRect.minX - frame.minX,
            y: screenRect.minY - frame.minY,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    private func cornerPoints(rect: NSRect) -> [NSPoint] {
        [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.maxY),
        ]
    }
}
