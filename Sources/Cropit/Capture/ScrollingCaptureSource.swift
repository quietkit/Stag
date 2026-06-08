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

        // Try scrolling via CGEvent simulation
        let visibleHeight = windowRect.height
        var scrollAttempts = 0
        let maxScrollAttempts = 30
        var lastImage = firstImage
        var hasMoreContent = true

        while hasMoreContent && scrollAttempts < maxScrollAttempts {
            scrollAttempts += 1

            // Scroll down by visibleHeight
            scrollWindow(pid: windowPID, lines: Int32(visibleHeight / 10))
            try await Task.sleep(nanoseconds: 300_000_000)

            let newImage = try await captureWindowImage(windowID: windowID)
            let newData = newImage.dataProvider?.data
            let lastData = lastImage.dataProvider?.data

            // If the image hasn't changed, we've reached the bottom
            if let newData, let lastData, CFDataGetLength(newData) == CFDataGetLength(lastData) {
                let newBytes = CFDataGetBytePtr(newData)
                let lastBytes = CFDataGetBytePtr(lastData)
                if memcmp(newBytes, lastBytes, CFDataGetLength(newData)) == 0 {
                    hasMoreContent = false
                    break
                }
            }

            frames.append((newImage, windowRect))
            lastImage = newImage
        }

        // Scroll back to top
        for _ in 0..<scrollAttempts {
            scrollWindow(pid: windowPID, lines: Int32(-Int(visibleHeight / 10)))
        }

        return try stitchFrames(frames, visibleHeight: visibleHeight)
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

    private func scrollWindow(pid: pid_t, lines: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: .activateIgnoringOtherApps)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
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

    private func stitchFrames(_ frames: [(image: CGImage, rect: CGRect)], visibleHeight: CGFloat) throws -> CGImage {
        guard !frames.isEmpty else { throw CaptureError.captureFailed(reason: "No frames captured") }

        let totalHeight: Int = frames.reduce(0) { $0 + $1.image.height }
        let width: Int = frames[0].image.width

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw CaptureError.captureFailed(reason: "Failed to create stitching context")
        }

        var yOffset: CGFloat = 0
        for (image, _) in frames {
            ctx.draw(image, in: CGRect(x: 0, y: yOffset, width: CGFloat(image.width), height: CGFloat(image.height)))
            yOffset += CGFloat(image.height)
        }

        guard let result = ctx.makeImage() else {
            throw CaptureError.captureFailed(reason: "Failed to stitch images")
        }
        return result
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
