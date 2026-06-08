import Cocoa
import SwiftUI
import ScreenCaptureKit

final class SelectionOverlayWindow: NSWindow {
    var onCapture: ((CGImage) -> Void)?
    var onCancel: (() -> Void)?

    init() {
        let screens = NSScreen.screens
        let totalFrame = screens.reduce(NSZeroRect) { $0.union($1.frame) }
        super.init(
            contentRect: totalFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = SelectionOverlayView(
            screenFrame: totalFrame,
            onCapture: { [weak self] rect in
                Task { await self?.performCapture(rect) }
            },
            onCancel: { [weak self] in
                self?.onCancel?()
                self?.close()
            }
        )
        let hosting = NSHostingView(rootView: overlayView)
        hosting.frame = NSRect(origin: .zero, size: totalFrame.size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func performCapture(_ viewRect: CGRect) async {
        guard let contentView = self.contentView else { return }
        let cvHeight = contentView.frame.height

        // Close overlay immediately so it's not captured in the screenshot
        close()

        let cgX = viewRect.minX + frame.origin.x
        let cgMinY = frame.origin.y + cvHeight - viewRect.maxY

        let selectionScreenOrigin = CGPoint(x: cgX, y: cgMinY)
        let selectionCGSize = CGSize(width: viewRect.width, height: viewRect.height)

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(
            NSRect(origin: selectionScreenOrigin, size: selectionCGSize)
        )}) else { return }

        let displayFrame = screen.frame
        let scale = screen.backingScaleFactor
        let cgMaxY = cgMinY + viewRect.height

        let imageCropRect = CGRect(
            x: (cgX - displayFrame.origin.x) * scale,
            y: (displayFrame.origin.y + displayFrame.height - cgMaxY) * scale,
            width: viewRect.width * scale,
            height: viewRect.height * scale
        )

        do {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? CGMainDisplayID()
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID })
            else { return }

            let config = SCStreamConfiguration()
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false

            let ourBundleID = Bundle.main.bundleIdentifier ?? ""
            let ourWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == ourBundleID }
            let filter = SCContentFilter(display: scDisplay, excludingWindows: ourWindows)
            let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let cropped = fullImage.cropping(to: imageCropRect) else { return }
            onCapture?(cropped)
        } catch {}
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
        close()
    }
}
