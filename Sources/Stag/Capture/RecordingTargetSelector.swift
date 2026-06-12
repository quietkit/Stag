import AppKit

enum RecordingTargetSelector {
    /// Region selector for screen recording / GIF. Uses the SAME rich selection
    /// overlay as area capture (adjustable handles, action bar, loupe, crosshair,
    /// window hover-highlight) but returns the selected screen rect instead of an
    /// image.
    static func select(mode: CaptureMode = .recording) async throws -> (CGRect, CGDirectDisplayID) {
        let prefs = AppStore.shared.preferences
        let freeze = prefs.freezeScreenBeforeCapture
        let showMagnifier = prefs.showMagnifier
        let dimOverlay = prefs.dimSelectionOverlay
        let showCrosshair = prefs.showCrosshair
        let directCapture = prefs.directCapture

        let composite = (freeze || showMagnifier) ? (try? await ScreenComposite.capture()) : nil

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let overlay = SelectionOverlayWindow(
                    frozenImage: freeze ? composite : nil,
                    sampleImage: composite,
                    dimOverlay: dimOverlay,
                    showMagnifier: showMagnifier,
                    showCrosshair: showCrosshair,
                    directCapture: directCapture,
                    mode: mode
                )
                overlay.onRectSelected = { rect, displayID in
                    continuation.resume(returning: (rect, displayID))
                }
                overlay.onCancel = {
                    continuation.resume(throwing: CaptureError.noActiveCapture)
                }
                overlay.show()
            }
        }
    }
}


