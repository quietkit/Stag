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

    private func _beginCapture(store: AppStore) async throws -> CaptureOutput {
        let (selectionRect, display) = try await RecordingTargetSelector.select()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == display }) else {
            throw CaptureError.captureFailed(reason: "Selected display not found")
        }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        let targetSize = CGSize(width: selectionRect.width, height: selectionRect.height)
        let config = RecordingConfig.from(preferences: store.preferences, targetSize: targetSize)

        let saveDir = URL(fileURLWithPath: store.preferences.expandedSavePath)
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let outputURL = saveDir.appendingPathComponent("\(filePrefix)_\(Date().shotTimestamp).\(fileExtension)")

        let hud = CaptureHUDWindow(
            statusProvider: { [weak self] in
                guard let self = self else { return "" }
                return self.statusFormat(self.recorder.recorderState, self.recorder)
            },
            onStop: { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    self.stopRequested = true
                    _ = await self.recorder.stopCapture()
                    self.stopContinuation?.resume()
                    self.stopContinuation = nil
                }
            }
        )

        store.captureState = .capturing
        hud.show()

        do {
            try await recorder.startCapture(filter: filter, config: config, outputURL: outputURL)
        } catch {
            hud.close()
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

        hud.close()
        store.captureState = .completed
        return .video(outputURL)
    }
}
