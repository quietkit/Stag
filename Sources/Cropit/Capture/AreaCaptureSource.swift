import Cocoa

final class AreaCaptureSource: CaptureSource {
    let type: CaptureType = .area

    func beginCapture(store: AppStore) async throws -> CaptureOutput {
        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            DispatchQueue.main.async {
                let overlay = SelectionOverlayWindow()
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
