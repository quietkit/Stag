import Cocoa
import ScreenCaptureKit

// MARK: - Capture Source

@MainActor
final class WindowCaptureSource: CaptureSource {
    nonisolated let type: CaptureType = .window
    private var overlayWindow: WindowPickerOverlay?

    func beginCapture(store: AppStore) async throws -> CaptureOutput {
        let image: CGImage = try await withCheckedThrowingContinuation { continuation in
            let overlay = WindowPickerOverlay()
            overlay.onWindowSelected = { [weak self] windowID in
                overlay.close()
                self?.overlayWindow = nil
                Task {
                    let result = await self?.captureWindow(id: windowID)
                    if let img = result {
                        continuation.resume(returning: img)
                    } else {
                        continuation.resume(throwing: CaptureError.captureFailed(reason: "Failed to capture window"))
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
        return .image(image)
    }

    private func captureWindow(id: CGWindowID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == id })
            else { return nil }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.showsCursor = false
            config.shouldBeOpaque = !AppStore.shared.preferences.windowCaptureShadow
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }
}

// MARK: - Picker Overlay Window

final class WindowPickerOverlay: NSWindow {
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onCancel: (() -> Void)?

    private let pickerView: WindowPickerContentView

    init() {
        let totalFrame = NSScreen.screens.reduce(NSZeroRect) { $0.union($1.frame) }
        pickerView = WindowPickerContentView()

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

// MARK: - Picker Content View

final class WindowPickerContentView: NSView {
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

        // Dim background
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.12))
        ctx.fill(dirtyRect)

        guard let rect = highlightedWindowRect, let name = highlightedWindowName else { return }

        let viewRect = WindowRectMapper.screenRectToView(rect, windowFrame: w.frame, isFlipped: isFlipped)

        // Highlight border
        ctx.setStrokeColor(CGColor(red: 0.25, green: 0.5, blue: 1, alpha: 0.9))
        ctx.setLineWidth(3)
        ctx.setShadow(offset: .zero, blur: 6, color: CGColor(red: 0.25, green: 0.5, blue: 1, alpha: 0.4))
        ctx.stroke(viewRect)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        // Corner handles
        let handleSize: CGFloat = 8
        let half = handleSize / 2
        ctx.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 1, alpha: 1))
        for corner in WindowRectMapper.cornerPoints(of: viewRect) {
            ctx.fillEllipse(in: CGRect(x: corner.x - half, y: corner.y - half, width: handleSize, height: handleSize))
        }

        // Window name label
        let label = name as NSString
        let labelSize = label.size(withAttributes: windowLabelAttrs)
        let labelW = min(labelSize.width + 12, viewRect.width + 20)
        let labelRect = NSRect(
            x: viewRect.midX - labelW / 2,
            y: viewRect.maxY + 8,
            width: labelW,
            height: 22
        )
        let bgPath = CGPath(roundedRect: labelRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(bgPath)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.75))
        ctx.fillPath()
        label.draw(at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 4),
                   withAttributes: windowLabelAttrs)
    }

    private let windowLabelAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white
    ]

}
