import Cocoa
import Combine

// MARK: - Value Types

enum CaptureFormat: String, Codable, CaseIterable {
    case png, jpeg
}

enum AfterCaptureAction: String, Codable, CaseIterable {
    case showOverlay, save, copy, openEditor, ask
}

enum ThumbnailPosition: String, Codable, CaseIterable {
    case bottomRight, bottomLeft, topRight, topLeft
}

enum ThumbnailSize: String, Codable, CaseIterable {
    case small, medium, large

    var size: CGSize {
        switch self {
        case .small:  return CGSize(width: 160, height: 100)
        case .medium: return CGSize(width: 220, height: 140)
        case .large:  return CGSize(width: 300, height: 190)
        }
    }
}

enum RecordingQuality: String, Codable, CaseIterable {
    case low, medium, high

    var fps: Int {
        switch self {
        case .low:    return 15
        case .medium: return 30
        case .high:   return 60
        }
    }
}

struct HotKeyCombination: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt // NSEvent.ModifierFlags.rawValue

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    static func `default`() -> [CaptureType: HotKeyCombination] {
        let cmdShift: UInt = NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
        return [
            .area:      HotKeyCombination(keyCode: 25, modifiers: cmdShift), // ⌘⇧5
            .window:    HotKeyCombination(keyCode: 20, modifiers: cmdShift), // ⌘⇧4 (placeholder)
            .fullscreen:HotKeyCombination(keyCode: 21, modifiers: cmdShift), // ⌘⇧3 (placeholder)
            .scrolling: HotKeyCombination(keyCode: 22, modifiers: cmdShift), // ⌘⇧2
            .recording: HotKeyCombination(keyCode: 26, modifiers: cmdShift), // ⌘⇧6
            .gif:      HotKeyCombination(keyCode: 27, modifiers: cmdShift), // ⌘⇧7
        ]
    }
}

// MARK: - Preferences

final class Preferences: ObservableObject {
    static let defaultsKey = "com.ganwar.Cropit.preferences"

    @Published var defaultFormat: CaptureFormat = .png
    @Published var jpegQuality: Double = 0.9
    @Published var savePath: String = "~/Desktop"
    @Published var afterCaptureAction: AfterCaptureAction = .showOverlay
    @Published var autoDismissDelay: TimeInterval = 5
    @Published var autoCopyToClipboard = false
    @Published var automaticSave = true
    @Published var thumbnailPosition: ThumbnailPosition = .bottomRight
    @Published var thumbnailSize: ThumbnailSize = .medium
    @Published var showMagnifier = true
    @Published var showCrosshair = true
    @Published var freezeScreenBeforeCapture = false
    @Published var hideDesktopIcons = false
    // Timer
    @Published var captureDelay: TimeInterval = 0 // 0 = off, 3, 5, 10
    // Recording
    @Published var recordingQuality: RecordingQuality = .high
    @Published var recordingFps: Int = 30
    @Published var recordSystemAudio = true
    @Published var recordMicrophone = false
    @Published var showCursorInRecording = true
    @Published var showKeystrokes = false
    @Published var uploadURL: String = ""

    @Published var hotkeys: [CaptureType: HotKeyCombination] = HotKeyCombination.default()

    var expandedSavePath: String {
        (savePath as NSString).expandingTildeInPath
    }

    init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode(Storage.self, from: data)
        else { return }

        defaultFormat = decoded.defaultFormat
        jpegQuality = decoded.jpegQuality
        savePath = decoded.savePath
        afterCaptureAction = decoded.afterCaptureAction
        autoDismissDelay = decoded.autoDismissDelay
        autoCopyToClipboard = decoded.autoCopyToClipboard
        automaticSave = decoded.automaticSave
        thumbnailPosition = decoded.thumbnailPosition
        thumbnailSize = decoded.thumbnailSize
        showMagnifier = decoded.showMagnifier
        showCrosshair = decoded.showCrosshair
        freezeScreenBeforeCapture = decoded.freezeScreenBeforeCapture
        hideDesktopIcons = decoded.hideDesktopIcons
        captureDelay = decoded.captureDelay
        recordingQuality = decoded.recordingQuality
        recordingFps = decoded.recordingFps
        recordSystemAudio = decoded.recordSystemAudio
        recordMicrophone = decoded.recordMicrophone
        showCursorInRecording = decoded.showCursorInRecording
        showKeystrokes = decoded.showKeystrokes
        uploadURL = decoded.uploadURL
        hotkeys = decoded.hotkeys
    }

    func save() {
        let storage = Storage(
            defaultFormat: defaultFormat,
            jpegQuality: jpegQuality,
            savePath: savePath,
            afterCaptureAction: afterCaptureAction,
            autoDismissDelay: autoDismissDelay,
            autoCopyToClipboard: autoCopyToClipboard,
            automaticSave: automaticSave,
            thumbnailPosition: thumbnailPosition,
            thumbnailSize: thumbnailSize,
            showMagnifier: showMagnifier,
            showCrosshair: showCrosshair,
            freezeScreenBeforeCapture: freezeScreenBeforeCapture,
            hideDesktopIcons: hideDesktopIcons,
            captureDelay: captureDelay,
            recordingQuality: recordingQuality,
            recordingFps: recordingFps,
            recordSystemAudio: recordSystemAudio,
            recordMicrophone: recordMicrophone,
            showCursorInRecording: showCursorInRecording,
            showKeystrokes: showKeystrokes,
            uploadURL: uploadURL,
            hotkeys: hotkeys
        )
        guard let data = try? JSONEncoder().encode(storage) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    // Flat Codable mirror to avoid @Published + Codable conflicts
    private struct Storage: Codable {
        var defaultFormat: CaptureFormat
        var jpegQuality: Double
        var savePath: String
        var afterCaptureAction: AfterCaptureAction
        var autoDismissDelay: TimeInterval
        var autoCopyToClipboard: Bool
        var automaticSave: Bool
        var thumbnailPosition: ThumbnailPosition
        var thumbnailSize: ThumbnailSize
        var showMagnifier: Bool
        var showCrosshair: Bool
        var freezeScreenBeforeCapture: Bool
        var hideDesktopIcons: Bool
        var captureDelay: TimeInterval
        var recordingQuality: RecordingQuality
        var recordingFps: Int
        var recordSystemAudio: Bool
        var recordMicrophone: Bool
        var showCursorInRecording: Bool
        var showKeystrokes: Bool
        var uploadURL: String
        var hotkeys: [CaptureType: HotKeyCombination]
    }
}
