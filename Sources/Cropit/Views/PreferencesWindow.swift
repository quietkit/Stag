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
        .padding(20)
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
                if prefs.defaultFormat == .jpeg {
                    Slider(value: $prefs.jpegQuality, in: 0.1...1.0, step: 0.1) {
                        Text("Quality: \(Int(prefs.jpegQuality * 100))%")
                    }
                }
                HStack {
                    Text("Save to")
                    TextField("~/Desktop/Cropit Screenshots", text: $prefs.savePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.prompt = "Select"
                        if panel.runModal() == .OK, let url = panel.url {
                            // Store as tilde-relative if inside home dir
                            let home = FileManager.default.homeDirectoryForCurrentUser.path
                            let path = url.path
                            prefs.savePath = path.hasPrefix(home)
                                ? "~" + path.dropFirst(home.count)
                                : path
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                HStack {
                    Text("File prefix")
                    TextField("Cropit_", text: $prefs.filePrefix)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: 160)
                    Text("e.g. \(prefs.filePrefix.isEmpty ? "Cropit_" : prefs.filePrefix)2026-01-01.png")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Section("After Capture") {
                Toggle("Show floating thumbnail", isOn: $prefs.showFloatingThumbnail)
                    .help("When off, captures are saved/copied immediately with no preview overlay — like Shottr's no-overlay mode. Click the thumbnail to open editor, or press Esc to dismiss it.")
                if prefs.showFloatingThumbnail {
                    Picker("Action", selection: $prefs.afterCaptureAction) {
                        ForEach(AfterCaptureAction.allCases, id: \.self) { a in
                            Text(actionDisplayName(a)).tag(a)
                        }
                    }
                    Slider(value: $prefs.autoDismissDelay, in: 1...30, step: 1) {
                        Text("Auto-dismiss after \(Int(prefs.autoDismissDelay))s")
                    }
                }
                Toggle("Auto-copy to clipboard", isOn: $prefs.autoCopyToClipboard)
                Toggle("Auto-save captures", isOn: $prefs.automaticSave)
            }
            Section("Thumbnail") {
                Picker("Position", selection: $prefs.thumbnailPosition) {
                    ForEach(ThumbnailPosition.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Picker("Size", selection: $prefs.thumbnailSize) {
                    ForEach(ThumbnailSize.allCases, id: \.self) { s in
                        Text("\(Int(s.size.width))×\(Int(s.size.height))").tag(s)
                    }
                }
                // auto-dismiss slider now lives in After Capture section
            }
            Section("Selection Overlay") {
                Toggle("Dim unselected area", isOn: $prefs.dimSelectionOverlay)
                    .help("When on, darkens the area outside your selection, making it stand out. Off by default for a minimal, Shottr-style interface.")
                Toggle("Show magnifier", isOn: $prefs.showMagnifier)
                Toggle("Show crosshair", isOn: $prefs.showCrosshair)
            }
        }
    }

    // MARK: Capture

    private var captureTab: some View {
        Form {
            Section("Timer") {
                Picker("Self-timer delay", selection: $prefs.captureDelay) {
                    Text("Off").tag(TimeInterval(0))
                    Text("3 seconds").tag(TimeInterval(3))
                    Text("5 seconds").tag(TimeInterval(5))
                    Text("10 seconds").tag(TimeInterval(10))
                }
            }
            Section("Preparation") {
                Toggle("Hide desktop icons before capture", isOn: $prefs.hideDesktopIcons)
                Toggle("Freeze screen before area selection", isOn: $prefs.freezeScreenBeforeCapture)
                Toggle("Include window shadow in window capture", isOn: $prefs.windowCaptureShadow)
            }
        }
    }

    // MARK: Recording

    private var recordingTab: some View {
        Form {
            Section("Quality") {
                Picker("Preset", selection: $prefs.recordingQuality) {
                    ForEach(RecordingQuality.allCases, id: \.self) { q in
                        Text("\(q.rawValue.capitalized) (\(q.fps) FPS)").tag(q)
                    }
                }
            }
            Section("Audio") {
                Toggle("Record system audio", isOn: $prefs.recordSystemAudio)
                Toggle("Record microphone", isOn: $prefs.recordMicrophone)
            }
            Section("Display") {
                Toggle("Show cursor", isOn: $prefs.showCursorInRecording)
                Toggle("Show keystrokes", isOn: $prefs.showKeystrokes)
                    .help("Displays pressed keys as an overlay during recording")
            }
            Section("Behavior") {
                Toggle("Auto-enable Do Not Disturb", isOn: $prefs.autoDND)
                    .help("Automatically enables DND during recording and restores afterward")
            }
        }
    }

    // MARK: Overlays (Webcam + Mouse clicks)

    private var overlaysTab: some View {
        Form {
            Section("Webcam Picture-in-Picture") {
                Toggle("Enable overlay", isOn: $prefs.webcamEnabled)
                if prefs.webcamEnabled {
                    Picker("Position", selection: $prefs.webcamPosition) {
                        ForEach(WebcamPosition.allCases, id: \.self) { pos in
                            Text(pos.displayName).tag(pos)
                        }
                    }
                    Picker("Size", selection: $prefs.webcamSize) {
                        ForEach(WebcamSize.allCases, id: \.self) { size in
                            Text("\(Int(size.size.width))×\(Int(size.size.height))").tag(size)
                        }
                    }
                }
            }
            Section("Mouse Clicks") {
                Toggle("Show click ripples", isOn: $prefs.showMouseClicks)
                    .help("Displays an animated ripple at each mouse click during recording")
            }
        }
    }

    // MARK: Shortcuts

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Capture Shortcuts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Click a shortcut to record a new key combination.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                List {
                    ForEach(CaptureType.allCases, id: \.self) { type in
                        shortcutRow(type)
                    }
                }
                .listStyle(.plain)
                .frame(height: 180)

                editorShortcutGuide
            }
        }
    }

    private func shortcutRow(_ type: CaptureType) -> some View {
        HStack {
            Label(typeDisplayName(type), systemImage: typeIcon(type))
                .font(.system(size: 12))
            Spacer()
            ShortcutRecorder(current: Binding(
                get: { prefs.hotkeys[type] ?? HotKeyCombination(keyCode: 0, modifiers: 0) },
                set: { prefs.hotkeys[type] = $0; prefs.save() }
            ))
        }
        .padding(.vertical, 2)
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
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.vertical, 4)
            Text("Editor Tool Shortcuts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.fixed(70))], spacing: 2) {
                let tools: [(String, String)] = [
                    ("Rectangle", "2"), ("Circle", "3"), ("Arrow", "1"), ("Line", "L"),
                    ("Text", "4"), ("Step Number", "8"), ("Freehand", "7"),
                    ("Highlight", "6"), ("Blur", "5"), ("Mosaic", "9"),
                    ("Emoji", "0"), ("Eraser", "X"), ("Eyedropper", "I"), ("Crop", "K"),
                ]
                ForEach(tools, id: \.0) { name, shortcut in
                    Text(name).font(.system(size: 10))
                    Text(shortcut).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
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
                    Text("Cloud Upload")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("https://example.com/upload", text: $prefs.uploadURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Text("PNG is POSTed to this URL. The response body is copied to clipboard.")
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
        Button {
            isRecording = true
            ShortcutCapture.begin { combo in
                if let combo = combo {
                    current = combo
                }
                isRecording = false
            }
        } label: {
            Text(displayText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isRecording ? .white : .secondary)
                .frame(width: 120, height: 22)
                .background(
                    Group {
                        if isRecording {
                            Color.accentColor
                        } else {
                            Color.secondary.opacity(0.08)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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

// MARK: - ShortcutCapture (one-shot key capture)

private final class ShortcutCapture: NSObject {
    private var monitor: Any?
    private let completion: (HotKeyCombination?) -> Void

    private init(completion: @escaping (HotKeyCombination?) -> Void) {
        self.completion = completion
        super.init()
    }

    static func begin(completion: @escaping (HotKeyCombination?) -> Void) {
        let capture = ShortcutCapture(completion: completion)
        capture.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.isEmpty else {
                NSEvent.removeMonitor(capture.monitor!)
                completion(nil)
                return nil
            }
            let combo = HotKeyCombination(keyCode: event.keyCode, modifiers: mods.rawValue)
            NSEvent.removeMonitor(capture.monitor!)
            completion(combo)
            return nil
        }
    }
}
