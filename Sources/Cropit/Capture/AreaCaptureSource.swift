import Cocoa
import ScreenCaptureKit

final class AreaCaptureSource: CaptureSource {
    let type: CaptureType = .area

    func beginCapture(store: AppStore) async throws -> CaptureOutput {
        let frozenImage: CGImage?
        if store.preferences.freezeScreenBeforeCapture {
            frozenImage = try? await captureAllScreensComposite(store: store)
        } else {
            frozenImage = nil
        }

        let dimOverlay = store.preferences.dimSelectionOverlay
        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            DispatchQueue.main.async {
                let overlay = SelectionOverlayWindow(frozenImage: frozenImage, dimOverlay: dimOverlay)
                overlay.onCapture = { image in
                    continuation.resume(returning: image)
                }
                overlay.onCancel = {
                    continuation.resume(throwing: CaptureError.noActiveCapture)
                }
                overlay.show()
            }
        }
        return .image(image)
    }

    private func captureAllScreensComposite(store: AppStore) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ourBundleID = Bundle.main.bundleIdentifier ?? ""
        let ourWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == ourBundleID
        }

        let screens = NSScreen.screens
        let totalFrame = screens.reduce(NSZeroRect) { $0.union($1.frame) }
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        let compositedWidth = Int(totalFrame.width * scale)
        let compositedHeight = Int(totalFrame.height * scale)

        // Capture each display
        var displayCaptures: [(image: CGImage, screen: NSScreen)] = []
        for screen in screens {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? CGMainDisplayID()
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else { continue }

            let config = SCStreamConfiguration()
            config.showsCursor = false
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let filter = SCContentFilter(display: scDisplay, excludingWindows: ourWindows)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            displayCaptures.append((image, screen))
        }

        guard !displayCaptures.isEmpty else {
            throw CaptureError.captureFailed(reason: "No displays captured")
        }

        // Composite into a single bitmap
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: compositedWidth,
            height: compositedHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw CaptureError.captureFailed(reason: "Failed to create bitmap context")
        }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: compositedWidth, height: compositedHeight))

        for (image, screen) in displayCaptures {
            let screenFrame = screen.frame
            let x = (screenFrame.origin.x - totalFrame.origin.x) * scale
            let y = (totalFrame.origin.y + totalFrame.height - screenFrame.origin.y - screenFrame.height) * scale
            let w = screenFrame.width * scale
            let h = screenFrame.height * scale
            ctx.draw(image, in: CGRect(x: x, y: y, width: w, height: h))
        }

        guard let result = ctx.makeImage() else {
            throw CaptureError.captureFailed(reason: "Failed to composite images")
        }
        return result
    }
}
