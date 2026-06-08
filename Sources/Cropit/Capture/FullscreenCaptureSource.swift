import Cocoa
import ScreenCaptureKit

final class FullscreenCaptureSource: CaptureSource {
    let type: CaptureType = .fullscreen

    func beginCapture(store: AppStore) async throws -> CaptureOutput {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.captureFailed(reason: "No display found")
        }

        let config = SCStreamConfiguration()
        config.showsCursor = store.preferences.showCrosshair
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let ourBundleID = Bundle.main.bundleIdentifier ?? ""
        let ourWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == ourBundleID
        }
        let filter = SCContentFilter(display: display, excludingWindows: ourWindows)

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return .image(image)
    }
}
