import Cocoa
import ScreenCaptureKit

final class AreaCaptureSource: CaptureSource {
    let type: CaptureType = .area

    func beginCapture(store: AppStore) async throws -> CaptureOutput {
        let freeze = store.preferences.freezeScreenBeforeCapture
        let showMagnifier = store.preferences.showMagnifier
        let showCrosshair = store.preferences.showCrosshair

        // Capture a clean composite (frozen background / true-color loupe source)
        // and enumerate windows (for hover-to-capture) concurrently so their
        // latencies overlap rather than add up.
        async let compositeTask: CGImage? = (freeze || showMagnifier) ? (try? await ScreenComposite.capture()) : nil
        async let windowsTask: [DetectedWindow] = WindowEnumerator.enumerate()
        let composite = await compositeTask
        let windows = await windowsTask
        let frozenImage = freeze ? composite : nil   // only shown when freeze is on
        let sampleImage = composite                  // loupe always samples this when present

        let dimOverlay = store.preferences.dimSelectionOverlay
        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            DispatchQueue.main.async {
                let overlay = SelectionOverlayWindow(frozenImage: frozenImage, sampleImage: sampleImage,
                                                     dimOverlay: dimOverlay, showMagnifier: showMagnifier,
                                                     showCrosshair: showCrosshair, windows: windows)
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
}
