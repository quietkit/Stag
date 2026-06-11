import Cocoa
import ScreenCaptureKit

final class AreaCaptureSource: CaptureSource {
    let type: CaptureType = .area

    func beginCapture(store: AppStore) async throws -> CaptureOutput {
        let freeze = store.preferences.freezeScreenBeforeCapture
        let showMagnifier = store.preferences.showMagnifier
        let showCrosshair = store.preferences.showCrosshair

        // Capture a clean composite (frozen background / true-color loupe source).
        let composite = (freeze || showMagnifier) ? (try? await ScreenComposite.capture()) : nil
        let frozenImage = freeze ? composite : nil   // only shown when freeze is on
        let sampleImage = composite                  // loupe always samples this when present

        let dimOverlay = store.preferences.dimSelectionOverlay
        let directCapture = store.preferences.directCapture
        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            DispatchQueue.main.async {
                let overlay = SelectionOverlayWindow(frozenImage: frozenImage, sampleImage: sampleImage,
                                                     dimOverlay: dimOverlay, showMagnifier: showMagnifier,
                                                     showCrosshair: showCrosshair, directCapture: directCapture, mode: .area)
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
