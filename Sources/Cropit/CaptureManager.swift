import Cocoa
import SwiftUI
import Vision

final class CaptureManager {
    private let store: AppStore
    private var currentSource: CaptureSource?
    private var thumbnailWindow: FloatingThumbnailWindow?
    private var lastCaptureType: CaptureType = .area
    private var recordingKeyMonitor: Any?
    private var recordingStopHandler: (() -> Void)?

    init(store: AppStore) {
        self.store = store
    }

    var isCapturing: Bool { currentSource != nil }

    @MainActor
    func startCapture(type: CaptureType = .area) {
        lastCaptureType = type
        guard currentSource == nil else { return }

        store.captureState = .selecting
        // Hide our own windows so the editor/history don't appear over (or show
        // through) the selection overlay during capture.
        CaptureWindowHider.shared.hide()
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
                    DesktopIconsManager.shared.restore(); CaptureWindowHider.shared.restore()
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
                            DesktopIconsManager.shared.restore(); CaptureWindowHider.shared.restore()
                            DNDManager.shared.restore()
                            self.currentSource = nil
                            self.store.resetState()
                        }
                        return
                    }
                }

                let output = try await source.beginCapture(store: self.store)
                await MainActor.run {
                    DesktopIconsManager.shared.restore(); CaptureWindowHider.shared.restore()
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
                    DesktopIconsManager.shared.restore(); CaptureWindowHider.shared.restore()
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
        DesktopIconsManager.shared.restore(); CaptureWindowHider.shared.restore()
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
            let source = MediaCaptureSource(
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
            setupRecordingEscapeHandling(for: source)
            return source
        case .gif:
            let source = MediaCaptureSource(
                type: .gif,
                recorder: GIFRecorder(),
                filePrefix: "GIF",
                fileExtension: "gif",
                statusFormat: { _, recorder in
                    guard let gr = recorder as? GIFRecorder else { return "" }
                    return "\(gr.frameCount) frames"
                }
            )
            setupRecordingEscapeHandling(for: source)
            return source
        }
    }

    @MainActor
    private func setupRecordingEscapeHandling(for source: MediaCaptureSource) {
        source.onRecordingStarted = { [weak self] in
            self?.installRecordingKeyMonitor(for: source)
        }
        source.onRecordingStopped = { [weak self] in
            self?.removeRecordingKeyMonitor()
        }
    }

    @MainActor
    private func installRecordingKeyMonitor(for source: MediaCaptureSource) {
        removeRecordingKeyMonitor()  // clean up any existing monitor first
        recordingStopHandler = { [weak source] in
            Task { @MainActor in
                source?.requestStop()
            }
        }
        recordingKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ESC key code is 53
            if event.keyCode == 53 {
                self?.recordingStopHandler?()
                return nil  // consume the event
            }
            return event
        }
    }

    @MainActor
    private func removeRecordingKeyMonitor() {
        if let monitor = recordingKeyMonitor {
            NSEvent.removeMonitor(monitor)
            recordingKeyMonitor = nil
        }
        recordingStopHandler = nil
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
            // Save first (when auto-save is on) and hand the editor the file path so
            // edits can be written back to it (and the history thumbnail refreshed).
            let savedPath = prefs.automaticSave
                ? saveImage(nsImage, type: type, addToHistory: true)?.path
                : nil
            openEditor(with: nsImage, filePath: savedPath)
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
            thumbnail = FloatingThumbnailWindow(autoDismissDelay: prefs.autoDismissDelay, position: prefs.thumbnailPosition)
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

    @discardableResult
    private func saveImage(_ image: NSImage, type: CaptureType, addToHistory: Bool) -> URL? {
        let prefs = store.preferences
        let saveDir = URL(fileURLWithPath: prefs.expandedSavePath)
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let ext = prefs.defaultFormat == .jpeg ? "jpg" : "png"
        let prefix = prefs.filePrefix.isEmpty ? "Cropit_" : prefs.filePrefix
        // Smart filename: insert the source app (e.g. "Slack") between the prefix
        // and the timestamp when available — falls back to prefix+timestamp.
        let slug = prefs.useSmartFilenames ? CaptureContext.shared.filenameSlug() : ""
        let middle = slug.isEmpty ? "" : "\(slug) "
        let url = saveDir.appendingPathComponent("\(prefix)\(middle)\(Date().shotTimestamp).\(ext)")

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
        return url
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

    private func openEditor(with image: NSImage, filePath: String? = nil) {
        let editor = EditorWindow(image: image, filePath: filePath)
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
        let showMagnifier = prefs.showMagnifier

        Task { @MainActor in
            // Clean loupe source so the magnifier reads true colors, not our overlay.
            let sample: CGImage? = showMagnifier ? try? await ScreenComposite.capture() : nil
            let overlay = SelectionOverlayWindow(frozenImage: nil, sampleImage: sample,
                                                 dimOverlay: dimOverlay, showMagnifier: showMagnifier,
                                                 showCrosshair: prefs.showCrosshair)
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
                        ToastWindow.show("No text found",
                                         icon: "text.slash",
                                         iconColor: .secondary)
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        let lines = text.components(separatedBy: "\n").count
                        ToastWindow.show("Copied \(lines) line\(lines == 1 ? "" : "s")",
                                         icon: "doc.on.clipboard.fill",
                                         iconColor: .green)
                    }
                }
            }
            request.recognitionLevel = .accurate
            // Auto-detect language so Arabic, English, French, etc. all work
            // without the caller having to configure anything.
            // usesLanguageCorrection is intentionally OFF for multilingual accuracy —
            // the English-tuned correction model corrupts Arabic and mixed scripts.
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = false

            try? VNImageRequestHandler(cgImage: cgImage, options: [:])
                .perform([request])
        }
    }
}
