import Cocoa
import SwiftUI
import Vision

final class CaptureManager {
    private let store: AppStore
    private var currentSource: CaptureSource?
    private var thumbnailWindow: FloatingThumbnailWindow?
    private var lastCaptureType: CaptureType = .area

    init(store: AppStore) {
        self.store = store
    }

    var isCapturing: Bool { currentSource != nil }

    @MainActor
    func startCapture(type: CaptureType = .area) {
        lastCaptureType = type
        guard currentSource == nil else { return }

        store.captureState = .selecting
        let source = makeSource(for: type)
        currentSource = source

        Task { [weak self] in
            guard let self = self else { return }

            let shouldHideDesktop = self.store.preferences.hideDesktopIcons && type.isScreenCapture
            if shouldHideDesktop {
                await MainActor.run { DesktopIconsManager.shared.hide() }
            }

            if shouldHideDesktop {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            // Auto-enable DND before recording
            if type.isScreenCapture == false && self.store.preferences.autoDND {
                await MainActor.run { DNDManager.shared.enable() }
            }

            guard await AppStore.requestPermissionAndCheck() else {
                await MainActor.run {
                    DesktopIconsManager.shared.restore()
                    DNDManager.shared.restore()
                    self.store.didFail(with: .screenRecordingPermissionDenied)
                    self.currentSource = nil
                }
                return
            }

            do {
                let delay = self.store.preferences.captureDelay
                if delay > 0 {
                    await MainActor.run {
                        self.store.captureState = .selecting
                    }
                    let overlay = CaptureCountdownOverlay(count: Int(delay))
                    let completed = await overlay.start()
                    await MainActor.run { overlay.close() }
                    guard completed else {
                        await MainActor.run {
                            DesktopIconsManager.shared.restore()
                            DNDManager.shared.restore()
                            self.currentSource = nil
                            self.store.resetState()
                        }
                        return
                    }
                }

                let output = try await source.beginCapture(store: self.store)
                await MainActor.run {
                    DesktopIconsManager.shared.restore()
                    DNDManager.shared.restore()
                    switch output {
                    case .image(let cgImage):
                        self.handleCapturedImage(cgImage, type: type)
                    case .video(let url):
                        self.handleCapturedVideo(url, type: type)
                    }
                    self.currentSource = nil
                }
            } catch {
                await MainActor.run {
                    DesktopIconsManager.shared.restore()
                    DNDManager.shared.restore()
                    self.currentSource = nil
                    // Cast first — pattern-matching on `Error` existential doesn't work directly
                    if let captureError = error as? CaptureError {
                        if case .noActiveCapture = captureError {
                            // User cancelled (ESC / click-away) — silent reset, no alert
                            self.store.resetState()
                        } else {
                            self.store.didFail(with: captureError)
                        }
                    } else {
                        self.store.didFail(with: .captureFailed(reason: error.localizedDescription))
                    }
                }
            }
        }
    }

    func cancelCapture() {
        currentSource = nil
        DesktopIconsManager.shared.restore()
        DNDManager.shared.restore()
        store.resetState()
    }

    // MARK: - Source Factory

    @MainActor
    private func makeSource(for type: CaptureType) -> CaptureSource {
        switch type {
        case .area:
            return AreaCaptureSource()
        case .window:
            return WindowCaptureSource()
        case .fullscreen:
            return FullscreenCaptureSource()
        case .scrolling:
            return ScrollingCaptureSource()
        case .recording:
            return MediaCaptureSource(
                type: .recording,
                recorder: ScreenRecorder(),
                filePrefix: "Recording",
                fileExtension: "mp4",
                statusFormat: { _, recorder in
                    guard let sr = recorder as? ScreenRecorder else { return "" }
                    let t = sr.elapsed
                    let m = Int(t) / 60
                    let s = Int(t) % 60
                    return String(format: "%02d:%02d", m, s)
                }
            )
        case .gif:
            return MediaCaptureSource(
                type: .gif,
                recorder: GIFRecorder(),
                filePrefix: "GIF",
                fileExtension: "gif",
                statusFormat: { _, recorder in
                    guard let gr = recorder as? GIFRecorder else { return "" }
                    return "\(gr.frameCount) frames"
                }
            )
        }
    }

    // MARK: - Image Pipeline

    private func handleCapturedImage(_ image: CGImage, type: CaptureType) {
        store.captureState = .processing
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        store.didCapture(image: nsImage, type: type)
        let prefs = store.preferences

        if prefs.autoCopyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([nsImage])
        }
        switch prefs.afterCaptureAction {
        case .showOverlay, .ask:
            if prefs.automaticSave { saveImage(nsImage, type: type, addToHistory: true) }
            if prefs.showFloatingThumbnail {
                showThumbnail(nsImage, captureType: type)
            }
        case .save:
            // Single save — automaticSave is redundant here
            saveImage(nsImage, type: type, addToHistory: true)
        case .copy:
            if prefs.automaticSave { saveImage(nsImage, type: type, addToHistory: true) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([nsImage])
        case .openEditor:
            if prefs.automaticSave { saveImage(nsImage, type: type, addToHistory: true) }
            openEditor(with: nsImage)
        }
    }

    // MARK: - Video Pipeline

    private func handleCapturedVideo(_ url: URL, type: CaptureType) {
        store.captureState = .completed

        // Show trimmer for screen recordings (not GIFs)
        if type == .recording {
            showVideoTrimmer(url)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.lastPathComponent, forType: .string)
    }

    private func showVideoTrimmer(_ url: URL) {
        let trimmer = VideoTrimmerWindow(videoURL: url) { outputURL in
            let finalURL = outputURL ?? url
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(finalURL.lastPathComponent, forType: .string)
        }
        trimmer.show()
    }

    // MARK: - Thumbnail

    private func showThumbnail(_ image: NSImage, captureType: CaptureType) {
        let prefs = store.preferences

        let thumbnail: FloatingThumbnailWindow
        if let existing = thumbnailWindow, existing.isVisible {
            thumbnail = existing
        } else {
            thumbnail = FloatingThumbnailWindow(autoDismissDelay: prefs.autoDismissDelay)
            self.thumbnailWindow = thumbnail
        }

        thumbnail.onSave = { [weak self] img in
            self?.saveImage(img, type: captureType, addToHistory: true)
        }
        thumbnail.onEdit = { [weak self] img in
            self?.openEditor(with: img)
        }
        thumbnail.onDiscard = { [weak self] img in
            self?.thumbnailWindow = nil
        }
        thumbnail.onCopy = { img in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
        }
        thumbnail.onReveal = { [weak self] img in
            guard let self = self else { return }
            self.saveImage(img, type: captureType, addToHistory: false)
            if let url = self.lastSavedURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        thumbnail.onPin = { img in
            PinboardManager.shared.pin(image: img)
        }
        thumbnail.onAutoSave = { [weak self] img in
            self?.saveImage(img, type: captureType, addToHistory: true)
        }
        thumbnail.onRetake = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in self.startCapture(type: self.lastCaptureType) }
        }

        thumbnail.pushEntry(image: image)
    }

    private var lastSavedURL: URL?

    // MARK: - Save

    private func saveImage(_ image: NSImage, type: CaptureType, addToHistory: Bool) {
        let prefs = store.preferences
        let saveDir = URL(fileURLWithPath: prefs.expandedSavePath)
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let ext = prefs.defaultFormat == .jpeg ? "jpg" : "png"
        let url = saveDir.appendingPathComponent("Cropit_\(Date().shotTimestamp).\(ext)")

        switch prefs.defaultFormat {
        case .png: image.pngWrite(to: url)
        case .jpeg: saveJPEG(image, to: url, quality: prefs.jpegQuality)
        }
        if prefs.autoCopyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
        lastSavedURL = url
        if addToHistory {
            let thumbDir = saveDir.appendingPathComponent(".thumbs")
            try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
            let thumbURL = thumbDir.appendingPathComponent("thumb_\(Date().shotTimestamp).jpg")
            saveJPEGThumbnail(image, to: thumbURL)
            store.recordCapture(image: image, type: type, saveURL: url, thumbnailURL: thumbURL)
        }
    }

    private func saveJPEG(_ image: NSImage, to url: URL, quality: Double) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return }
        let props: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: quality]
        guard let data = bitmap.representation(using: .jpeg, properties: props) else { return }
        try? data.write(to: url)
    }

    private func saveJPEGThumbnail(_ image: NSImage, to url: URL) {
        let maxDim: CGFloat = 320
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return }
        let scale = min(maxDim / w, maxDim / h, 1.0)
        let thumbSize = CGSize(width: w * scale, height: h * scale)
        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1)
        thumb.unlockFocus()
        saveJPEG(thumb, to: url, quality: 0.7)
    }

    // MARK: - Editor

    private func openEditor(with image: NSImage) {
        let editor = EditorWindow(image: image)
        editor.show()
    }

    // MARK: - OCR Capture

    /// Show the area-selection overlay, capture the selected region, run Vision OCR,
    /// copy the recognised text to the clipboard and show a brief HUD notification.
    @MainActor
    func startOCRCapture() {
        guard currentSource == nil else { return }
        store.captureState = .selecting

        let prefs = store.preferences
        let dimOverlay = prefs.dimSelectionOverlay
        let overlay = SelectionOverlayWindow(frozenImage: nil, dimOverlay: dimOverlay)
        overlay.onCapture = { [weak self] cgImage in
            guard let self else { return }
            Task { @MainActor in
                await self.runOCR(on: cgImage)
                self.store.resetState()
            }
        }
        overlay.onCancel = { [weak self] in
            self?.store.resetState()
        }
        overlay.show()
    }

    private func runOCR(on cgImage: CGImage) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let request = VNRecognizeTextRequest { request, _ in
                defer { continuation.resume() }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                DispatchQueue.main.async {
                    if text.isEmpty {
                        self.showOCRNotification("No text found")
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.showOCRNotification("Copied \(text.count) characters")
                    }
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            try? VNImageRequestHandler(cgImage: cgImage, options: [:])
                .perform([request])
        }
    }

    private func showOCRNotification(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "OCR Complete"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
