import SwiftUI
import Combine
import ScreenCaptureKit
import CoreGraphics

// MARK: - App State

enum CaptureState: Equatable {
    case idle
    case selecting
    case capturing
    case processing
    case completed
    case error(CaptureError)

    static func == (lhs: CaptureState, rhs: CaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.selecting, .selecting), (.capturing, .capturing),
             (.processing, .processing), (.completed, .completed):
            return true
        case (.error(let a), .error(let b)):
            return a.localizedDescription == b.localizedDescription
        default:
            return false
        }
    }
}

struct CaptureResult {
    let image: NSImage
    let type: CaptureType
    let date: Date
    let fileSize: Int64
}

// MARK: - App Store

final class AppStore: ObservableObject {
    static let shared = AppStore()

    let preferences: Preferences
    let history: CaptureHistoryStore

    @Published var captureState: CaptureState = .idle
    @Published var lastCaptureResult: CaptureResult?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.preferences = Preferences()
        self.history = CaptureHistoryStore()

        preferences.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        preferences.$showKeystrokes
            .receive(on: DispatchQueue.main)
            .sink { enabled in
                if enabled { KeystrokeManager.shared.start() }
                else { KeystrokeManager.shared.stop() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func didCapture(image: NSImage, type: CaptureType) {
        let fileSize = Int64(image.pngData?.count ?? 0)
        let result = CaptureResult(image: image, type: type, date: Date(), fileSize: fileSize)
        lastCaptureResult = result
        captureState = .completed
    }

    func didFail(with error: CaptureError) {
        captureState = .error(error)
        DispatchQueue.main.async {
            let alert = NSAlert(error: error)
            alert.runModal()
            self.captureState = .idle
        }
    }

    func recordCapture(image: NSImage, type: CaptureType, saveURL: URL, thumbnailURL: URL) {
        let record = CaptureRecord(image: image, type: type, saveURL: saveURL, thumbnailURL: thumbnailURL,
                                   appName: CaptureContext.shared.sourceAppName)
        history.add(record)
    }

    func resetState() {
        captureState = .idle
    }

    // MARK: - Screen Recording Permission

    static func requestPermissionAndCheck() async -> Bool {
        // On macOS 13-, CGRequestScreenCaptureAccess shows a prompt.
        // On macOS 14+, it's a no-op but doesn't hurt to call it first.
        if #available(macOS 13, *) {
            CGRequestScreenCaptureAccess()
        }

        // The real permission check — SCShareableContent is the authority on macOS 14+.
        // System triggers a prompt on first call (if entitlement is properly set up).
        // For ad-hoc signed dev builds the prompt may not appear; user must add manually.
        // We poll for 90s to give the user time to do that.
        for i in 0..<90 {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return true
            } catch {
                if i == 0 {
                    // First failure. System prompt may have been shown (or not).
                    // On macOS 14+, the user might need to manually add the app.
                    // The CaptureManager will show recovery instructions.
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        return false
    }
}
