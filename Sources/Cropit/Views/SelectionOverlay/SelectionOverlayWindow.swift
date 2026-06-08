import Cocoa
import SwiftUI
import ScreenCaptureKit

final class SelectionOverlayWindow: NSWindow {
    var onCapture: ((CGImage) -> Void)?
    var onCancel: (() -> Void)?
    private let frozenImage: CGImage?

    init(frozenImage: CGImage? = nil, dimOverlay: Bool = true) {
        self.frozenImage = frozenImage
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
            frozenImage: frozenImage,
            onCapture: { [weak self] rect in
                Task { await self?.performCapture(rect) }
            },
            onCancel: { [weak self] in
                self?.onCancel?()
                self?.close()
            },
            dimOverlay: dimOverlay
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

        close()

        let cgX = viewRect.minX + frame.origin.x
        let cgMinY = frame.origin.y + cvHeight - viewRect.maxY

        let selectionScreenOrigin = CGPoint(x: cgX, y: cgMinY)
        let selectionCGSize = CGSize(width: viewRect.width, height: viewRect.height)

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(
            NSRect(origin: selectionScreenOrigin, size: selectionCGSize)
        )}) else { return }

        let displayFrame = screen.frame
        let cgMaxY = cgMinY + viewRect.height

        if let frozen = frozenImage {
            // frozenImage covers the entire totalFrame — derive scale from its actual pixel dimensions
            let screens = NSScreen.screens
            let totalFrame = screens.reduce(NSZeroRect) { $0.union($1.frame) }
            guard totalFrame.width > 0, totalFrame.height > 0 else { return }
            let frozenScaleX = CGFloat(frozen.width) / totalFrame.width
            let frozenScaleY = CGFloat(frozen.height) / totalFrame.height
            let frozenCropRect = CGRect(
                x: (cgX - totalFrame.origin.x) * frozenScaleX,
                y: (totalFrame.origin.y + totalFrame.height - cgMaxY) * frozenScaleY,
                width: viewRect.width * frozenScaleX,
                height: viewRect.height * frozenScaleY
            )
            guard let cropped = frozen.cropping(to: frozenCropRect) else { return }
            onCapture?(cropped)
            return
        }

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
            // Derive actual pixel scale from the returned image (avoids HiDPI assumption errors)
            let actualScaleX = CGFloat(fullImage.width) / displayFrame.width
            let actualScaleY = CGFloat(fullImage.height) / displayFrame.height
            let actualCropRect = CGRect(
                x: (cgX - displayFrame.origin.x) * actualScaleX,
                y: (displayFrame.origin.y + displayFrame.height - cgMaxY) * actualScaleY,
                width: viewRect.width * actualScaleX,
                height: viewRect.height * actualScaleY
            )
            guard let cropped = fullImage.cropping(to: actualCropRect) else { return }
            onCapture?(cropped)
        } catch {}
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
        close()
    }

    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
