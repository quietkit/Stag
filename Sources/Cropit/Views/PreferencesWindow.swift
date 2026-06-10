import Cocoa
import SwiftUI

final class PreferencesWindow: NSWindow, NSWindowDelegate {
    private let hostingView: NSHostingView<PreferencesView>

    init() {
        let size = NSSize(width: 900, height: 600)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )

        let prefs = AppStore.shared.preferences
        hostingView = NSHostingView(rootView: PreferencesView(prefs: prefs))

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Settings"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 700, height: 500)
        setFrameAutosaveName("PreferencesWindow")
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
        delegate = self
    }

    func show() {
        WindowLifecycle.didOpen(self)
    }

    // ESC closes the preferences window
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    func windowWillClose(_ notification: Notification) {
        WindowLifecycle.didClose(self)
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Preferences View

private struct PreferencesView: View {
    @ObservedObject var prefs: Preferences
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general, capture, recording, overlays, shortcuts, advanced

        var icon: String {
            switch self {
            case .general:   return "gearshape"
            case .capture:   return "camera"
            case .recording: return "video"
            case .overlays:  return "square.on.square"
            case .shortcuts: return "keyboard"
            case .advanced:  return "wrench"
            }
        }

        var label: String {
            switch self {
            case .general:   return "General"
            case .capture:   return "Capture"
            case .recording: return "Recording"
            case .overlays:  return "Overlays"
            case .shortcuts: return "Shortcuts"
            case .advanced:  return "Advanced"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.label, systemImage: tab.icon)
                    .font(.system(size: 12))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160, idealWidth: 170, maxWidth: 180)
            .navigationSplitViewColumnWidth(min: 155, ideal: 165, max: 180)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { prefs.save() }
    }

    @ViewBuilder
    private var detailView: some View {
        Group {
            switch selectedTab {
            case .general:   generalTab
            case .capture:   captureTab
            case .recording: recordingTab
            case .overlays:  overlaysTab
            case .shortcuts: shortcutsTab
            case .advanced:  advancedTab
            }
        }
        .padding(24)
        .font(.system(size: 12))  // Larger default text
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Section("Output") {
                Picker("Format", selection: $prefs.defaultFormat) {
                    ForEach(CaptureFormat.allCases, id: \.self) { fmt in
                        Text(fmt.rawValue.uppercased()).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)

                if prefs.defaultFormat == .jpeg {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quality: \(Int(prefs.jpegQuality * 100))%").font(.system(size: 13, weight: .semibold))
                        Slider(value: $prefs.jpegQuality, in: 0.1...1.0, step: 0.1)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Save Location").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        TextField("~/Desktop/Cropit Screenshots", text: $prefs.savePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .controlSize(.large)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            panel.prompt = "Select"
                            if panel.runModal() == .OK, let url = panel.url {
                                let home = FileManager.default.homeDirectoryForCurrentUser.path
                                let path = url.path
                                prefs.savePath = path.hasPrefix(home)
                                    ? "~" + path.dropFirst(home.count)
                                    : path
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("File Prefix").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        TextField("Cropit_", text: $prefs.filePrefix)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: 180)
                            .controlSize(.large)
                        Text("e.g. \(filenamePreview)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Toggle("Smart filenames (include the source app)", isOn: $prefs.useSmartFilenames)
                    .font(.system(size: 13))
                    .help("Names files after the app you captured, e.g. \"Safari 2026-…\". Falls back to the timestamp when unknown.")
            }
            Section("After Capture") {
                Toggle("Show floating thumbnail", isOn: $prefs.showFloatingThumbnail)
                    .font(.system(size: 13))
                    .help("When off, captures are saved/copied immediately with no preview overlay — like Shottr's no-overlay mode.")
                if prefs.showFloatingThumbnail {
                    Picker("Action", selection: $prefs.afterCaptureAction) {
                        ForEach(AfterCaptureAction.allCases, id: \.self) { a in
                            Text(actionDisplayName(a)).tag(a)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Auto-dismiss after \(Int(prefs.autoDismissDelay))s").font(.system(size: 13, weight: .semibold))
                        Slider(value: $prefs.autoDismissDelay, in: 1...30, step: 1)
                    }
                }
                Toggle("Auto-copy to clipboard", isOn: $prefs.autoCopyToClipboard)
                    .font(.system(size: 13))
                Toggle("Auto-save captures", isOn: $prefs.automaticSave)
                    .font(.system(size: 13))
            }

            Section("Thumbnail Position & Size") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Position").font(.system(size: 12, weight: .semibold))
                        Picker("", selection: $prefs.thumbnailPosition) {
                            ForEach(ThumbnailPosition.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Size").font(.system(size: 12, weight: .semibold))
                        Picker("", selection: $prefs.thumbnailSize) {
                            ForEach(ThumbnailSize.allCases, id: \.self) { s in
                                Text("\(Int(s.size.width))×\(Int(s.size.height))").tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            Section("Selection Overlay") {
                Toggle("Dim unselected area", isOn: $prefs.dimSelectionOverlay)
                    .font(.system(size: 13))
                    .help("When on, darkens the area outside your selection, making it stand out. Off by default for a minimal interface.")
                Toggle("Show magnifier", isOn: $prefs.showMagnifier)
                    .font(.system(size: 13))
                Toggle("Show crosshair", isOn: $prefs.showCrosshair)
                    .font(.system(size: 13))
            }
        }
    }

    // MARK: Capture

    private var captureTab: some View {
        Form {
            Section("Self-Timer") {
                Picker("Delay", selection: $prefs.captureDelay) {
                    Text("Off").tag(TimeInterval(0))
                    Text("3 seconds").tag(TimeInterval(3))
                    Text("5 seconds").tag(TimeInterval(5))
                    Text("10 seconds").tag(TimeInterval(10))
                }
                .pickerStyle(.segmented)
            }
            Section("Preparation Options") {
                Toggle("Hide desktop icons before capture", isOn: $prefs.hideDesktopIcons)
                    .font(.system(size: 13))
                Toggle("Freeze screen before area selection", isOn: $prefs.freezeScreenBeforeCapture)
                    .font(.system(size: 13))
                Toggle("Include window shadow in window capture", isOn: $prefs.windowCaptureShadow)
                    .font(.system(size: 13))
            }
        }
    }

    // MARK: Recording

    private var recordingTab: some View {
        Form {
            Section("Video Quality") {
                Picker("Quality Preset", selection: $prefs.recordingQuality) {
                    ForEach(RecordingQuality.allCases, id: \.self) { q in
                        Text("\(q.rawValue.capitalized) (\(q.fps) FPS)").tag(q)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Audio Options") {
                Toggle("Record system audio", isOn: $prefs.recordSystemAudio)
                    .font(.system(size: 13))
                Toggle("Record microphone", isOn: $prefs.recordMicrophone)
                    .font(.system(size: 13))
            }
            Section("Display Options") {
                Toggle("Show cursor during recording", isOn: $prefs.showCursorInRecording)
                    .font(.system(size: 13))
                Toggle("Show keystrokes", isOn: $prefs.showKeystrokes)
                    .font(.system(size: 13))
                    .help("Displays pressed keys as an overlay during recording")
            }
            Section("System Behavior") {
                Toggle("Auto-enable Do Not Disturb", isOn: $prefs.autoDND)
                    .font(.system(size: 13))
                    .help("Automatically enables DND during recording and restores afterward")
            }
        }
    }

    // MARK: Overlays (Webcam + Mouse clicks)

    private var overlaysTab: some View {
        Form {
            Section("Webcam Picture-in-Picture") {
                Toggle("Enable webcam overlay", isOn: $prefs.webcamEnabled)
                    .font(.system(size: 13))
                if prefs.webcamEnabled {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Position").font(.system(size: 12, weight: .semibold))
                            Picker("", selection: $prefs.webcamPosition) {
                                ForEach(WebcamPosition.allCases, id: \.self) { pos in
                                    Text(pos.displayName).tag(pos)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Size").font(.system(size: 12, weight: .semibold))
                            Picker("", selection: $prefs.webcamSize) {
                                ForEach(WebcamSize.allCases, id: \.self) { size in
                                    Text("\(Int(size.size.width))×\(Int(size.size.height))").tag(size)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            Section("Mouse Click Indicator") {
                Toggle("Show click ripples", isOn: $prefs.showMouseClicks)
                    .font(.system(size: 13))
                    .help("Displays an animated ripple at each mouse click during recording")
            }
        }
    }

    // MARK: Shortcuts

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Capture Shortcuts").font(.system(size: 15, weight: .semibold))
                    Text("Click a shortcut, then press a combination with ⌘ ⌥ ⌃ or ⇧. Press Esc to cancel, or ✕ to clear.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    let types = Array(CaptureType.allCases.enumerated())
                    ForEach(types, id: \.element) { idx, type in
                        shortcutRow(type)
                        if idx < types.count - 1 {
                            Divider().padding(.leading, 38)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.1), lineWidth: 1))

                editorShortcutGuide
            }
            .padding(.bottom, 8)
        }
    }

    private func shortcutRow(_ type: CaptureType) -> some View {
        HStack(spacing: 10) {
            Image(systemName: typeIcon(type))
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
                .frame(width: 18)
            Text(typeDisplayName(type)).font(.system(size: 13))
            Spacer()
            ShortcutRecorder(current: Binding(
                get: { prefs.hotkeys[type] ?? HotKeyCombination(keyCode: 0, modifiers: 0) },
                set: {
                    prefs.hotkeys[type] = $0
                    prefs.save()
                    NotificationCenter.default.post(name: .cropitHotkeysChanged, object: nil)
                }
            ))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func typeIcon(_ type: CaptureType) -> String {
        switch type {
        case .area:      return "rectangle.dashed"
        case .window:    return "macwindow"
        case .fullscreen:return "rectangle.fill"
        case .scrolling: return "arrow.down.to.line"
        case .recording: return "record.circle"
        case .gif:       return "play.square"
        }
    }

    private func typeDisplayName(_ type: CaptureType) -> String {
        switch type {
        case .area:      return "Capture Area"
        case .window:    return "Capture Window"
        case .fullscreen:return "Capture Fullscreen"
        case .scrolling: return "Scrolling Capture"
        case .recording: return "Screen Recording"
        case .gif:       return "GIF Recording"
        }
    }

    private var editorShortcutGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Editor Tool Shortcuts").font(.system(size: 15, weight: .semibold))
            let tools: [(String, String)] = [
                ("Arrow", "1"), ("Rectangle", "2"), ("Circle", "3"), ("Text", "4"),
                ("Blur", "5"), ("Highlight", "6"), ("Freehand", "7"), ("Step Number", "8"),
                ("Mosaic", "9"), ("Emoji", "0"), ("Line", "L"), ("Eraser", "X"),
                ("Eyedropper", "I"), ("Crop", "K"),
            ]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(tools, id: \.0) { name, key in
                    HStack(spacing: 6) {
                        Text(name).font(.system(size: 11))
                        Spacer(minLength: 4)
                        Text(key)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 16)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.04)))
                }
            }
        }
    }

    // MARK: Advanced

    private var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Section {
                    Text("URL Scheme")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Trigger captures by opening cropit:// URLs in the browser, Raycast, Alfred, or scripts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox(label: Label("Available Commands", systemImage: "link")) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(urlCommands, id: \.url) { cmd in
                            HStack(alignment: .top, spacing: 8) {
                                Text(cmd.url)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.accentColor)
                                    .frame(maxWidth: 160, alignment: .leading)
                                Text(cmd.desc)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(6)
                }
                .padding(.top, 4)

                Section {
                    Text("Cloud Upload / Share Links")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Text("Upload to your OWN endpoint (server, S3-compatible gateway, image host). Nothing is ever uploaded automatically — only when you press Upload.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Picker("", selection: $prefs.uploadMethod) {
                                Text("POST").tag("POST")
                                Text("PUT").tag("PUT")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 110)
                            TextField("https://example.com/upload", text: $prefs.uploadURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }

                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Multipart field").font(.system(size: 10)).foregroundColor(.secondary)
                                TextField("empty = raw body", text: $prefs.uploadFieldName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Response link key").font(.system(size: 10)).foregroundColor(.secondary)
                                TextField("e.g. data.link", text: $prefs.uploadResponseKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Headers (one per line: Key: Value)").font(.system(size: 10)).foregroundColor(.secondary)
                            TextEditor(text: $prefs.uploadHeaders)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 54)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                        }

                        Text("Raw mode posts the PNG as the body. Multipart sends it as a file field. The returned link (whole body, or the JSON key above) is copied to your clipboard.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }
        }
    }

    private struct URLCommandHelp {
        let url: String
        let desc: String
    }

    private var urlCommands: [URLCommandHelp] {
        [
            .init(url: "cropit://capture", desc: "Area capture (default)"),
            .init(url: "cropit://capture?type=window", desc: "Window capture"),
            .init(url: "cropit://capture?type=fullscreen", desc: "Fullscreen capture"),
            .init(url: "cropit://capture?type=scrolling", desc: "Scrolling capture"),
            .init(url: "cropit://capture?type=recording", desc: "Screen recording"),
            .init(url: "cropit://capture?type=gif", desc: "GIF recording"),
            .init(url: "cropit://capture?delay=5", desc: "With 5s self-timer"),
            .init(url: "cropit://preferences", desc: "Open settings"),
            .init(url: "cropit://history", desc: "Open history browser"),
        ]
    }

    // MARK: Helpers

    private var filenamePreview: String {
        let prefix = prefs.filePrefix.isEmpty ? "Cropit_" : prefs.filePrefix
        let mid = prefs.useSmartFilenames ? "Safari " : ""
        return "\(prefix)\(mid)2026-01-01.png"
    }

    private func actionDisplayName(_ action: AfterCaptureAction) -> String {
        switch action {
        case .showOverlay: return "Floating thumbnail"
        case .save:        return "Save directly"
        case .copy:        return "Copy to clipboard"
        case .openEditor:  return "Open editor"
        case .ask:         return "Ask each time"
        }
    }
}

// MARK: - ShortcutRecorder Component

private struct ShortcutRecorder: View {
    @Binding var current: HotKeyCombination
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if isRecording {
                    ShortcutCapture.cancelActive()      // click again to cancel
                } else {
                    isRecording = true
                    ShortcutCapture.begin { combo in
                        if let combo = combo { current = combo }
                        isRecording = false
                    }
                }
            } label: {
                Text(displayText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isRecording ? .white : .secondary)
                    .frame(width: 116, height: 22)
                    .background(isRecording ? Color.accentColor : Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Clear button — only when a shortcut is set and not recording.
            Button {
                current = HotKeyCombination(keyCode: 0, modifiers: 0)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(!isRecording && current.keyCode != 0 ? 1 : 0)
            .help("Clear shortcut")
        }
    }

    private var displayText: String {
        if isRecording { return "Press shortcut\u{2026}" }
        if current.keyCode == 0 { return "None" }
        var parts: [String] = []
        let flags = current.modifierFlags
        if flags.contains(.control) { parts.append("\u{2303}") }
        if flags.contains(.option)  { parts.append("\u{2325}") }
        if flags.contains(.shift)   { parts.append("\u{21E7}") }
        if flags.contains(.command) { parts.append("\u{2318}") }
        let key = keyName(current.keyCode)
        parts.append(key)
        return parts.joined()
    }

    private func keyName(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            18: "1", 19: "2", 20: "3", 21: "4", 22: "5", 23: "6",
            24: "7", 25: "8", 26: "9", 29: "0",
            12: "Q", 13: "W", 14: "E", 15: "R", 16: "T", 17: "Y",
            32: "U", 34: "I", 31: "O", 35: "P",
            0:  "A", 1:  "S", 2:  "D", 3:  "F", 4:  "H", 5:  "G",
            38: "J", 40: "K", 37: "L",
            45: "N", 46: "M",
            6:  "Z", 7:  "X", 8:  "C", 9:  "V", 11: "B",
            49: "Space",
            36: "Return", 53: "Esc", 48: "Tab", 51: "Delete",
        ]
        return map[code] ?? "Key\(code)"
    }
}

// MARK: - ShortcutCapture (single-flight key capture)

/// Records one global-hotkey combination. Only ONE capture can be active at a
/// time — starting a new one (or clicking elsewhere) cancels the previous, so
/// rows can never get stuck showing "Press shortcut…".
private final class ShortcutCapture {
    private static var active: ShortcutCapture?

    private var monitor: Any?
    private let completion: (HotKeyCombination?) -> Void

    private init(completion: @escaping (HotKeyCombination?) -> Void) {
        self.completion = completion
    }

    static func begin(completion: @escaping (HotKeyCombination?) -> Void) {
        cancelActive()                       // enforce single-flight
        let capture = ShortcutCapture(completion: completion)
        active = capture
        capture.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged { return nil }       // ignore bare modifier presses
            if event.keyCode == 53 { capture.finish(nil); return nil }   // Esc cancels
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.isEmpty else { return nil }              // require ≥1 modifier; swallow bare keys
            capture.finish(HotKeyCombination(keyCode: event.keyCode, modifiers: mods.rawValue))
            return nil
        }
    }

    /// Cancels any in-progress capture (resets its row to its previous value).
    static func cancelActive() { active?.finish(nil) }

    private func finish(_ combo: HotKeyCombination?) {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if ShortcutCapture.active === self { ShortcutCapture.active = nil }
        completion(combo)
    }
}
