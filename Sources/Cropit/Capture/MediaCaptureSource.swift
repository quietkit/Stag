import Cocoa
import ScreenCaptureKit

@MainActor
final class MediaCaptureSource: CaptureSource {
    let type: CaptureType
    private let recorder: any CaptureRecorder
    private let statusFormat: (RecorderState, any CaptureRecorder) -> String
    private let filePrefix: String
    private let fileExtension: String
    private var stopRequested = false
    private var stopContinuation: CheckedContinuation<Void, Never>?
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    private var borderOverlay: RecordBorderOverlay?

    init(
        type: CaptureType,
        recorder: any CaptureRecorder,
        filePrefix: String,
        fileExtension: String,
        statusFormat: @escaping (RecorderState, any CaptureRecorder) -> String
    ) {
        self.type = type
        self.recorder = recorder
        self.filePrefix = filePrefix
        self.fileExtension = fileExtension
        self.statusFormat = statusFormat
    }

    nonisolated func beginCapture(store: AppStore) async throws -> CaptureOutput {
        try await _beginCapture(store: store)
    }

    func requestStop() {
        borderOverlay?.close()
        borderOverlay = nil
        stopRequested = true
        Task { @MainActor in
            _ = await recorder.stopCapture()
            self.stopContinuation?.resume()
            self.stopContinuation = nil
        }
    }

    private func _beginCapture(store: AppStore) async throws -> CaptureOutput {
        let captureMode: CaptureMode = type == .gif ? .gif : .recording
        let (selectionRect, display) = try await RecordingTargetSelector.select(mode: captureMode)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == display }) else {
            throw CaptureError.captureFailed(reason: "Selected display not found")
        }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        // Compute display-relative captureRect (y=0 at top-left of display, in logical points).
        // selectionRect is in absolute Cocoa screen coords (y=0 at bottom).
        let nsScreen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == display
        }
        // Show border around the recording region
        let border = RecordBorderOverlay(rect: selectionRect)
        border.show()
        borderOverlay = border

        let captureRect: CGRect? = nsScreen.map { screen in
            let df = screen.frame
            return CGRect(
                x: selectionRect.origin.x - df.origin.x,
                y: df.maxY - selectionRect.maxY,         // flip to top-left origin
                width: selectionRect.width,
                height: selectionRect.height
            )
        }

        let targetSize = CGSize(width: selectionRect.width, height: selectionRect.height)
        let config = RecordingConfig.from(preferences: store.preferences, targetSize: targetSize, captureRect: captureRect)

        let saveDir = URL(fileURLWithPath: store.preferences.expandedSavePath)
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let outputURL = saveDir.appendingPathComponent("\(filePrefix)_\(Date().shotTimestamp).\(fileExtension)")

        // Use a weak-box so onStop can close the HUD window immediately without
        // waiting for encoding (which can take 2+ seconds for GIF).
        final class Box<T: AnyObject> { weak var value: T? }
        let hudBox = Box<CaptureHUDWindow>()

        let hud = CaptureHUDWindow(
            statusProvider: { [weak self] in
                guard let self = self else { return "" }
                return self.statusFormat(self.recorder.recorderState, self.recorder)
            },
            onStop: { [weak self, hudBox] in
                guard let self = self else { return }
                // Close the HUD right away — don't wait for encoding.
                hudBox.value?.close()
                requestStop()
            }
        )
        hudBox.value = hud

        store.captureState = .capturing
        hud.show()
        onRecordingStarted?()

        do {
            try await recorder.startCapture(filter: filter, config: config, outputURL: outputURL)
        } catch {
            borderOverlay?.close()
            borderOverlay = nil
            hud.close()
            onRecordingStopped?()
            throw error
        }

        // Wait for stop signal — handle race if onStop already fired
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if self.stopRequested {
                continuation.resume()
            } else {
                self.stopContinuation = continuation
            }
        }

        // hud may already be closed by onStop; guard against double-close
        if hud.isVisible { hud.close() }
        onRecordingStopped?()
        store.captureState = .completed
        return .video(outputURL)
    }
}
