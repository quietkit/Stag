import Cocoa
import SwiftUI

final class CaptureManager {
    private let store: AppStore
    private var currentSource: CaptureSource?
    private var thumbnailWindow: FloatingThumbnailWindow?

    init(store: AppStore) {
        self.store = store
    }

    var isCapturing: Bool { currentSource != nil }

    @MainActor
    func startCapture(type: CaptureType = .area) {
        guard currentSource == nil else { return }

        store.captureState = .selecting
        let source = makeSource(for: type)
        currentSource = source

        Task { [weak self] in
            guard let self = self else { return }

            guard await AppStore.requestPermissionAndCheck() else {
                await MainActor.run {
                    self.store.didFail(with: .screenRecordingPermissionDenied)
                    self.currentSource = nil
                }
                return
            }

            do {
                // Self-timer countdown
                let delay = self.store.preferences.captureDelay
                if delay > 0 {
                    await MainActor.run {
                        self.store.captureState = .selecting
                    }
                    let overlay = CaptureCountdownOverlay(count: Int(delay))
                    let completed = await overlay.start()
                    await MainActor.run { overlay.close() }
                    guard completed else {
                        self.currentSource = nil
                        self.store.resetState()
                        return
                    }
                }

                let output = try await source.beginCapture(store: self.store)
                await MainActor.run {
                    switch output {
                    case .image(let cgImage):
                        self.handleCapturedImage(cgImage, type: type)
                    case .video(let url):
                        self.handleCapturedVideo(url)
                    }
                }
            } catch {
                if let captureError = error as? CaptureError {
                    self.store.didFail(with: captureError)
                } else {
                    self.store.didFail(with: .captureFailed(reason: error.localizedDescription))
                }
            }
            self.currentSource = nil
        }
    }

    func cancelCapture() {
        currentSource = nil
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
            return AreaCaptureSource()
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
        if prefs.automaticSave {
            saveImage(nsImage, type: type, addToHistory: true)
        }
        switch prefs.afterCaptureAction {
        case .showOverlay, .ask:
            showThumbnail(nsImage)
        case .save:
            saveImage(nsImage, type: type, addToHistory: true)
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([nsImage])
        case .openEditor:
            openEditor(with: nsImage)
        }
    }

    // MARK: - Video Pipeline

    private func handleCapturedVideo(_ url: URL) {
        store.captureState = .completed
        // For now: copy path to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.lastPathComponent, forType: .string)
    }

    // MARK: - Thumbnail

    private func showThumbnail(_ image: NSImage) {
        let prefs = store.preferences

        let thumbnail: FloatingThumbnailWindow
        if let existing = thumbnailWindow, existing.isVisible {
            thumbnail = existing
        } else {
            thumbnail = FloatingThumbnailWindow(autoDismissDelay: prefs.autoDismissDelay)
            self.thumbnailWindow = thumbnail
        }

        // Always set callbacks (in case window was reused from a prior session)
        thumbnail.onSave = { [weak self] img in
            self?.saveImage(img, type: .area, addToHistory: true)
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
            self.saveImage(img, type: .area, addToHistory: false)
            if let url = self.lastSavedURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        thumbnail.onPin = { img in
            PinboardManager.shared.pin(image: img)
        }
        thumbnail.onAutoSave = { [weak self] img in
            self?.saveImage(img, type: .area, addToHistory: true)
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
        let thumbSize = CGSize(width: 320, height: 240)
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
}
