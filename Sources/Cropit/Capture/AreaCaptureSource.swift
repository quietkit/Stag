import Cocoa
import ScreenCaptureKit

final class AreaCaptureSource: CaptureSource {
    let type: CaptureType = .area

    func beginCapture(store: AppStore) async throws -> CaptureOutput {
        let freeze = store.preferences.freezeScreenBeforeCapture
        let showMagnifier = store.preferences.showMagnifier

        // Capture one clean composite if we need a frozen background OR a true-color
        // loupe source. The loupe must sample a pristine screen, not our dim overlay.
        let composite: CGImage? = (freeze || showMagnifier) ? try? await ScreenComposite.capture() : nil
        let frozenImage = freeze ? composite : nil   // only shown when freeze is on
        let sampleImage = composite                  // loupe always samples this when present

        let dimOverlay = store.preferences.dimSelectionOverlay
        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            DispatchQueue.main.async {
                let overlay = SelectionOverlayWindow(frozenImage: frozenImage, sampleImage: sampleImage,
                                                     dimOverlay: dimOverlay, showMagnifier: showMagnifier)
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
