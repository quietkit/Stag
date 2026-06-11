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

    var displayName: String {
        switch self {
        case .bottomRight: return "Bottom Right"
        case .bottomLeft:  return "Bottom Left"
        case .topRight:    return "Top Right"
        case .topLeft:     return "Top Left"
        }
    }
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

enum WebcamPosition: String, Codable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var displayName: String {
        switch self {
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum WebcamSize: String, Codable, CaseIterable {
    case small, medium, large

    var size: CGSize {
        switch self {
        case .small:  return CGSize(width: 160, height: 120)
        case .medium: return CGSize(width: 240, height: 180)
        case .large:  return CGSize(width: 320, height: 240)
        }
    }
}

struct HotKeyCombination: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    static func `default`() -> [CaptureType: HotKeyCombination] {
        let cmdShift: UInt = NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
        return [
            .area:      HotKeyCombination(keyCode: 18, modifiers: cmdShift),
            .window:    HotKeyCombination(keyCode: 19, modifiers: cmdShift),
            .fullscreen:HotKeyCombination(keyCode: 20, modifiers: cmdShift),
            .scrolling: HotKeyCombination(keyCode: 21, modifiers: cmdShift),
            // NOTE: macOS digit keycodes are NOT sequential — kVK_ANSI_5 = 23 and
            // kVK_ANSI_6 = 22. Previously these were swapped, so ⌘⇧6 ("Record GIF"
            // in the UI) actually fired the screen recorder.
            .recording: HotKeyCombination(keyCode: 23, modifiers: cmdShift),  // ⌘⇧5
            .gif:       HotKeyCombination(keyCode: 22, modifiers: cmdShift),  // ⌘⇧6
        ]
    }
}

// MARK: - Preferences

final class Preferences: ObservableObject {
    static let defaultsKey = "com.ganwar.Cropit.preferences"

    @Published var defaultFormat: CaptureFormat = .png
    @Published var jpegQuality: Double = 0.9
    @Published var savePath: String = "~/Desktop/Cropit Screenshots"
    @Published var filePrefix: String = "Cropit_"
    @Published var useSmartFilenames: Bool = true
    @Published var settingsAdvancedMode: Bool = false   // Settings: Simple vs Advanced
    private var overlayMinimalApplied = false            // one-time minimal-overlay migration
    @Published var afterCaptureAction: AfterCaptureAction = .openEditor
    @Published var autoDismissDelay: TimeInterval = 5
    @Published var autoCopyToClipboard = true
    @Published var automaticSave = true
    @Published var thumbnailPosition: ThumbnailPosition = .bottomRight
    @Published var thumbnailSize: ThumbnailSize = .medium
    @Published var showMagnifier = false
    @Published var showCrosshair = false
    @Published var freezeScreenBeforeCapture = false
    @Published var hideDesktopIcons = false
    @Published var captureDelay: TimeInterval = 0
    @Published var recordingQuality: RecordingQuality = .high
    @Published var recordSystemAudio = true
    @Published var recordMicrophone = false
    @Published var showCursorInRecording = true
    @Published var showKeystrokes = false
    @Published var uploadURL: String = ""
    @Published var uploadMethod: String = "POST"        // POST or PUT
    @Published var uploadFieldName: String = ""         // multipart field; empty = raw body
    @Published var uploadHeaders: String = ""           // "Key: Value" per line
    @Published var uploadResponseKey: String = ""       // JSON key path to the link

    var uploadConfig: UploadConfig {
        UploadConfig(
            endpoint: uploadURL,
            method: uploadMethod,
            fieldName: uploadFieldName,
            headers: UploadConfig.parseHeaders(uploadHeaders),
            responseURLKey: uploadResponseKey
        )
    }

    // Sprint C — Webcam PiP
    @Published var webcamEnabled = false
    @Published var webcamPosition: WebcamPosition = .bottomRight
    @Published var webcamSize: WebcamSize = .medium

    // Sprint C — Mouse clicks
    @Published var showMouseClicks = false

    // Sprint C — Auto DND
    @Published var autoDND = false

    @Published var windowCaptureShadow: Bool = true
    /// When false: no floating thumbnail after capture — image goes directly to editor / clipboard
    @Published var showFloatingThumbnail: Bool = false
    /// When true: dims the unselected area (non-selection), making selection stand out
    @Published var dimSelectionOverlay: Bool = false
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
        filePrefix = decoded.filePrefix ?? "Cropit_"
        useSmartFilenames = decoded.useSmartFilenames ?? true
        settingsAdvancedMode = decoded.settingsAdvancedMode ?? false
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
        recordSystemAudio = decoded.recordSystemAudio
        recordMicrophone = decoded.recordMicrophone
        showCursorInRecording = decoded.showCursorInRecording
        showKeystrokes = decoded.showKeystrokes
        uploadURL = decoded.uploadURL
        uploadMethod = decoded.uploadMethod ?? "POST"
        uploadFieldName = decoded.uploadFieldName ?? ""
        uploadHeaders = decoded.uploadHeaders ?? ""
        uploadResponseKey = decoded.uploadResponseKey ?? ""
        webcamEnabled = decoded.webcamEnabled
        webcamPosition = decoded.webcamPosition
        webcamSize = decoded.webcamSize
        showMouseClicks = decoded.showMouseClicks
        autoDND = decoded.autoDND
        hotkeys = decoded.hotkeys
        // Migrate the historically swapped Record/GIF keycodes (5↔6). Anyone who
        // still has the old buggy defaults gets the corrected ⌘⇧5 / ⌘⇧6 binding.
        let cmdShift: UInt = NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
        if hotkeys[.recording]?.keyCode == 22, hotkeys[.recording]?.modifiers == cmdShift,
           hotkeys[.gif]?.keyCode == 23, hotkeys[.gif]?.modifiers == cmdShift {
            hotkeys[.recording] = HotKeyCombination(keyCode: 23, modifiers: cmdShift)
            hotkeys[.gif] = HotKeyCombination(keyCode: 22, modifiers: cmdShift)
        }
        windowCaptureShadow = decoded.windowCaptureShadow
        showFloatingThumbnail = decoded.showFloatingThumbnail
        dimSelectionOverlay = decoded.dimSelectionOverlay

        // One-time migration: the selection overlay is now minimal by default
        // (no dim / magnifier / crosshair). Apply that once to existing installs.
        overlayMinimalApplied = decoded.overlayMinimalApplied ?? false
        if !overlayMinimalApplied {
            dimSelectionOverlay = false
            showMagnifier = false
            showCrosshair = false
            overlayMinimalApplied = true
        }
    }

    func save() {
        let storage = Storage(
            defaultFormat: defaultFormat,
            jpegQuality: jpegQuality,
            savePath: savePath,
            filePrefix: filePrefix,
            useSmartFilenames: useSmartFilenames,
            settingsAdvancedMode: settingsAdvancedMode,
            overlayMinimalApplied: overlayMinimalApplied,
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
            recordSystemAudio: recordSystemAudio,
            recordMicrophone: recordMicrophone,
            showCursorInRecording: showCursorInRecording,
            showKeystrokes: showKeystrokes,
            uploadURL: uploadURL,
            uploadMethod: uploadMethod,
            uploadFieldName: uploadFieldName,
            uploadHeaders: uploadHeaders,
            uploadResponseKey: uploadResponseKey,
            webcamEnabled: webcamEnabled,
            webcamPosition: webcamPosition,
            webcamSize: webcamSize,
            showMouseClicks: showMouseClicks,
            autoDND: autoDND,
            hotkeys: hotkeys,
            windowCaptureShadow: windowCaptureShadow,
            showFloatingThumbnail: showFloatingThumbnail,
            dimSelectionOverlay: dimSelectionOverlay
        )
        guard let data = try? JSONEncoder().encode(storage) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private struct Storage: Codable {
        var defaultFormat: CaptureFormat
        var jpegQuality: Double
        var savePath: String
        var filePrefix: String?          // optional for backward compatibility
        var useSmartFilenames: Bool?     // optional for backward compatibility
        var settingsAdvancedMode: Bool?  // optional for backward compatibility
        var overlayMinimalApplied: Bool? // optional for backward compatibility
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
        var recordSystemAudio: Bool
        var recordMicrophone: Bool
        var showCursorInRecording: Bool
        var showKeystrokes: Bool
        var uploadURL: String
        var uploadMethod: String?
        var uploadFieldName: String?
        var uploadHeaders: String?
        var uploadResponseKey: String?
        var webcamEnabled: Bool
        var webcamPosition: WebcamPosition
        var webcamSize: WebcamSize
        var showMouseClicks: Bool
        var autoDND: Bool
        var hotkeys: [CaptureType: HotKeyCombination]
        var windowCaptureShadow: Bool
        var showFloatingThumbnail: Bool
        var dimSelectionOverlay: Bool
    }
}
