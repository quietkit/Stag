import Cocoa
import SwiftUI

final class PreferencesWindow: NSWindow, NSWindowDelegate {
    private let hostingView: NSHostingView<PreferencesView>

    init() {
        let size = NSSize(width: 1000, height: 680)
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
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isReleasedWhenClosed = false
        minSize = NSSize(width: 820, height: 560)
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
            case .general:   return "gearshape.fill"
            case .capture:   return "camera.fill"
            case .recording: return "video.fill"
            case .overlays:  return "square.on.square"
            case .shortcuts: return "keyboard.fill"
            case .advanced:  return "wrench.and.screwdriver.fill"
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

        var tint: Color {
            switch self {
            case .general:   return .gray
            case .capture:   return .blue
            case .recording: return .red
            case .overlays:  return .purple
            case .shortcuts: return .orange
            case .advanced:  return .teal
            }
        }

        var subtitle: String {
            switch self {
            case .general:   return "Output format, saving, and after-capture behavior."
            case .capture:   return "Timer, preparation, and selection behavior."
            case .recording: return "Video quality, audio, and recording overlays."
            case .overlays:  return "Webcam picture-in-picture and click effects."
            case .shortcuts: return "Global hotkeys and editor tool keys."
            case .advanced:  return "Automation URL scheme and custom upload endpoint."
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { prefs.save() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App header
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Stag")
                        .font(.system(size: 15, weight: .bold))
                    Text("Settings")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 40)       // clear the (transparent) titlebar / traffic lights
            .padding(.bottom, 18)

            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SidebarItem(
                    icon: tab.icon,
                    tint: tab.tint,
                    label: tab.label,
                    selected: selectedTab == tab
                ) { selectedTab = tab }
            }
            .padding(.horizontal, 10)

            Spacer()

            Text("Stag \(appVersion)")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: 210)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedTab {
        case .general:   generalTab
        case .capture:   captureTab
        case .recording: recordingTab
        case .overlays:  overlaysTab
        case .shortcuts: shortcutsTab
        case .advanced:  advancedTab
        }
    }

    // MARK: General

    private var generalTab: some View {
        SettingsPage(tab: .general) {
            SettingsCard(title: "Output") {
                SettingsRow(title: "Image format") {
                    Picker("", selection: $prefs.defaultFormat) {
                        ForEach(CaptureFormat.allCases, id: \.self) { fmt in
                            Text(fmt.rawValue.uppercased()).tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
                if prefs.defaultFormat == .jpeg {
                    CardDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("JPEG quality — \(Int(prefs.jpegQuality * 100))%")
                            .font(.system(size: 13))
                        Slider(value: $prefs.jpegQuality, in: 0.1...1.0, step: 0.1)
                    }
                    .settingsRowPadding()
                }
            }

            SettingsCard(title: "Saving") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save location").font(.system(size: 13))
                    HStack(spacing: 8) {
                        TextField("~/Desktop/Stag Screenshots", text: $prefs.savePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
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
                    }
                }
                .settingsRowPadding()

                CardDivider()

                SettingsRow(title: "File prefix", subtitle: "e.g. \(filenamePreview)") {
                    TextField("Stag_", text: $prefs.filePrefix)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 150)
                }

                CardDivider()

                ToggleRow(title: "Smart filenames",
                          subtitle: "Include the captured app's name in the filename",
                          isOn: $prefs.useSmartFilenames)
            }

            SettingsCard(title: "After Capture") {
                ToggleRow(title: "Show floating thumbnail",
                          subtitle: "Preview overlay after each capture; off saves/copies instantly",
                          isOn: $prefs.showFloatingThumbnail)
                if prefs.showFloatingThumbnail {
                    CardDivider()
                    SettingsRow(title: "Default action") {
                        Picker("", selection: $prefs.afterCaptureAction) {
                            ForEach(AfterCaptureAction.allCases, id: \.self) { a in
                                Text(actionDisplayName(a)).tag(a)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    CardDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Auto-dismiss after \(Int(prefs.autoDismissDelay)) seconds")
                            .font(.system(size: 13))
                        Slider(value: $prefs.autoDismissDelay, in: 1...30, step: 1)
                    }
                    .settingsRowPadding()
                    CardDivider()
                    SettingsRow(title: "Thumbnail position") {
                        Picker("", selection: $prefs.thumbnailPosition) {
                            ForEach(ThumbnailPosition.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    CardDivider()
                    SettingsRow(title: "Thumbnail size") {
                        Picker("", selection: $prefs.thumbnailSize) {
                            ForEach(ThumbnailSize.allCases, id: \.self) { s in
                                Text("\(Int(s.size.width))×\(Int(s.size.height))").tag(s)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }
                CardDivider()
                ToggleRow(title: "Auto-copy to clipboard", isOn: $prefs.autoCopyToClipboard)
                CardDivider()
                ToggleRow(title: "Auto-save captures", isOn: $prefs.automaticSave)
            }

            SettingsCard(title: "Selection Overlay") {
                ToggleRow(title: "Dim unselected area",
                          subtitle: "Darken everything outside your selection",
                          isOn: $prefs.dimSelectionOverlay)
                CardDivider()
                ToggleRow(title: "Show magnifier",
                          subtitle: "Pixel loupe with color readout while selecting",
                          isOn: $prefs.showMagnifier)
                CardDivider()
                ToggleRow(title: "Show crosshair",
                          subtitle: "Full-screen guide lines that follow the cursor",
                          isOn: $prefs.showCrosshair)
            }
        }
    }

    // MARK: Capture

    private var captureTab: some View {
        SettingsPage(tab: .capture) {
            SettingsCard(title: "Self-Timer") {
                SettingsRow(title: "Delay before capture") {
                    Picker("", selection: $prefs.captureDelay) {
                        Text("Off").tag(TimeInterval(0))
                        Text("3s").tag(TimeInterval(3))
                        Text("5s").tag(TimeInterval(5))
                        Text("10s").tag(TimeInterval(10))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            SettingsCard(title: "Preparation") {
                ToggleRow(title: "Hide desktop icons before capture",
                          isOn: $prefs.hideDesktopIcons)
                CardDivider()
                ToggleRow(title: "Freeze screen before area selection",
                          subtitle: "Selection happens over a frozen snapshot of the screen",
                          isOn: $prefs.freezeScreenBeforeCapture)
                CardDivider()
                ToggleRow(title: "Include window shadow in window capture",
                          isOn: $prefs.windowCaptureShadow)
            }

            SettingsCard(title: "Selection Mode") {
                ToggleRow(title: "Capture immediately",
                          subtitle: "Capture as soon as you release the mouse. Off shows resize handles to fine-tune the selection first.",
                          isOn: $prefs.directCapture)
            }
        }
    }

    // MARK: Recording

    private var recordingTab: some View {
        SettingsPage(tab: .recording) {
            SettingsCard(title: "Video Quality") {
                SettingsRow(title: "Quality preset") {
                    Picker("", selection: $prefs.recordingQuality) {
                        ForEach(RecordingQuality.allCases, id: \.self) { q in
                            Text("\(q.rawValue.capitalized) · \(q.fps) FPS").tag(q)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                }
            }

            SettingsCard(title: "Audio") {
                ToggleRow(title: "Record system audio", isOn: $prefs.recordSystemAudio)
                CardDivider()
                ToggleRow(title: "Record microphone", isOn: $prefs.recordMicrophone)
            }

            SettingsCard(title: "Display") {
                ToggleRow(title: "Show cursor during recording",
                          isOn: $prefs.showCursorInRecording)
                CardDivider()
                ToggleRow(title: "Show keystrokes",
                          subtitle: "Displays pressed keys as an overlay during recording",
                          isOn: $prefs.showKeystrokes)
            }

            SettingsCard(title: "System") {
                ToggleRow(title: "Auto-enable Do Not Disturb",
                          subtitle: "Silence notifications during recording, restore after",
                          isOn: $prefs.autoDND)
            }
        }
    }

    // MARK: Overlays (Webcam + Mouse clicks)

    private var overlaysTab: some View {
        SettingsPage(tab: .overlays) {
            SettingsCard(title: "Webcam Picture-in-Picture") {
                ToggleRow(title: "Enable webcam overlay",
                          subtitle: "Show your camera in a corner of recordings",
                          isOn: $prefs.webcamEnabled)
                if prefs.webcamEnabled {
                    CardDivider()
                    SettingsRow(title: "Position") {
                        Picker("", selection: $prefs.webcamPosition) {
                            ForEach(WebcamPosition.allCases, id: \.self) { pos in
                                Text(pos.displayName).tag(pos)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    CardDivider()
                    SettingsRow(title: "Size") {
                        Picker("", selection: $prefs.webcamSize) {
                            ForEach(WebcamSize.allCases, id: \.self) { size in
                                Text("\(Int(size.size.width))×\(Int(size.size.height))").tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }
            }

            SettingsCard(title: "Mouse Click Indicator") {
                ToggleRow(title: "Show click ripples",
                          subtitle: "Animated ripple at each mouse click during recording",
                          isOn: $prefs.showMouseClicks)
            }
        }
    }

    // MARK: Shortcuts

    private var shortcutsTab: some View {
        SettingsPage(tab: .shortcuts) {
            SettingsCard(title: "Capture Shortcuts",
                         footer: "Click a shortcut, then press a combination with ⌘ ⌥ ⌃ or ⇧. Press Esc to cancel, or ✕ to clear.") {
                let types = Array(CaptureType.allCases.enumerated())
                ForEach(types, id: \.element) { idx, type in
                    shortcutRow(type)
                    if idx < types.count - 1 {
                        CardDivider()
                    }
                }
            }

            SettingsCard(title: "Editor Tool Keys",
                         footer: "Click a key badge and press any key (with optional ⇧) to remap. Press Esc to cancel.") {
                EditorHotkeyEditor(hotkeys: $prefs.editorHotkeys, onSave: { prefs.save() })
                    .settingsRowPadding()
            }
        }
    }

    private func shortcutRow(_ type: CaptureType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: typeIcon(type))
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 22)
            Text(typeDisplayName(type)).font(.system(size: 13))
            Spacer()
            ShortcutRecorder(current: Binding(
                get: { prefs.hotkeys[type] ?? HotKeyCombination(keyCode: 0, modifiers: 0) },
                set: {
                    prefs.hotkeys[type] = $0
                    prefs.save()
                    NotificationCenter.default.post(name: .stagHotkeysChanged, object: nil)
                }
            ))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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


    // MARK: Advanced

    private var advancedTab: some View {
        SettingsPage(tab: .advanced) {
            SettingsCard(title: "URL Scheme",
                         footer: "Trigger captures by opening stag:// URLs from the browser, Raycast, Alfred, or scripts.") {
                VStack(alignment: .leading, spacing: 0) {
                    let cmds = Array(urlCommands.enumerated())
                    ForEach(cmds, id: \.element.url) { idx, cmd in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(cmd.url)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.accentColor)
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Text(cmd.desc)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        if idx < cmds.count - 1 { CardDivider() }
                    }
                }
            }

            SettingsCard(title: "Cloud Upload / Share Links",
                         footer: "Raw mode posts the PNG as the body. Multipart sends it as a file field. The returned link (whole body, or the JSON key above) is copied to your clipboard. Nothing is uploaded automatically — only when you press Upload.") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Picker("", selection: $prefs.uploadMethod) {
                            Text("POST").tag("POST")
                            Text("PUT").tag("PUT")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 120)
                        TextField("https://example.com/upload", text: $prefs.uploadURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Multipart field").font(.system(size: 11)).foregroundColor(.secondary)
                            TextField("empty = raw body", text: $prefs.uploadFieldName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Response link key").font(.system(size: 11)).foregroundColor(.secondary)
                            TextField("e.g. data.link", text: $prefs.uploadResponseKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Headers (one per line: Key: Value)")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        TextEditor(text: $prefs.uploadHeaders)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 60)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                    }
                }
                .settingsRowPadding()
            }
        }
    }

    private struct URLCommandHelp {
        let url: String
        let desc: String
    }

    private var urlCommands: [URLCommandHelp] {
        [
            .init(url: "stag://capture", desc: "Area capture (default)"),
            .init(url: "stag://capture?type=window", desc: "Window capture"),
            .init(url: "stag://capture?type=fullscreen", desc: "Fullscreen capture"),
            .init(url: "stag://capture?type=scrolling", desc: "Scrolling capture"),
            .init(url: "stag://capture?type=recording", desc: "Screen recording"),
            .init(url: "stag://capture?type=gif", desc: "GIF recording"),
            .init(url: "stag://capture?delay=5", desc: "With 5s self-timer"),
            .init(url: "stag://preferences", desc: "Open settings"),
            .init(url: "stag://history", desc: "Open history browser"),
        ]
    }

    // MARK: Helpers

    private var filenamePreview: String {
        let prefix = prefs.filePrefix.isEmpty ? "Stag_" : prefs.filePrefix
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

// MARK: - Design System Components

/// Sidebar navigation row: colored icon tile + label, accent fill when selected.
private struct SidebarItem: View {
    let icon: String
    let tint: Color
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 23, height: 23)
                    .background(RoundedRectangle(cornerRadius: 6).fill(tint.gradient))
                Text(label)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .white : .primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor
                          : (hovering ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .padding(.vertical, 1)
    }
}

/// Scrollable page with a large title header and a centered, width-capped column.
private struct SettingsPage<Content: View>: View {
    let tab: PreferencesView.SettingsTab
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tab.label)
                        .font(.system(size: 26, weight: .bold))
                    Text(tab.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 2)

                content
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 28)
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

/// Rounded card grouping related settings rows, with optional header + footer.
private struct SettingsCard<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)
            }
        }
    }
}

/// Inset divider between card rows.
private struct CardDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}

/// Standard card row: title (+ optional subtitle) left, control right.
private struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Card row with a modern switch instead of a checkbox.
private struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

private extension View {
    /// Padding matching SettingsRow, for free-form card content (sliders, fields).
    func settingsRowPadding() -> some View {
        self.padding(.horizontal, 14).padding(.vertical, 12)
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
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isRecording ? .white : .secondary)
                    .frame(width: 124, height: 24)
                    .background(isRecording ? Color.accentColor : Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .handCursorOnHover()

            // Clear button — only when a shortcut is set and not recording.
            Button {
                current = HotKeyCombination(keyCode: 0, modifiers: 0)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
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
        return current.displayString
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

// MARK: - EditorHotkeyEditor

private struct EditorHotkeyEditor: View {
    @Binding var hotkeys: [String: String]
    let onSave: () -> Void

    @State private var recordingTool: String? = nil
    @State private var conflictAlert: ConflictInfo? = nil

    private struct ConflictInfo: Identifiable {
        let id = UUID()
        let newTool: String
        let newKey: String
        let existingTool: String
    }

    // Ordered list of (toolRaw, displayName)
    private let toolRows: [(String, String)] = [
        ("arrow", "Arrow"),         ("curvedArrow", "Curved Arrow"),
        ("rect", "Rectangle"),      ("circle", "Circle"),
        ("text", "Text"),           ("line", "Line"),
        ("blur", "Blur"),           ("highlight", "Highlight"),
        ("smartHighlight", "Smart Highlight"), ("freehand", "Freehand"),
        ("stepNumber", "Step Number"), ("mosaic", "Mosaic"),
        ("emoji", "Emoji"),         ("ruler", "Ruler"),
        ("spotlight", "Spotlight"), ("magnifierCallout", "Magnifier"),
        ("eraser", "Eraser"),       ("eyedropper", "Eyedropper"),
        ("crop", "Crop"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(toolRows, id: \.0) { raw, name in
                    toolRow(raw: raw, name: name)
                }
            }

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    withAnimation {
                        hotkeys = Preferences.defaultEditorHotkeys
                        onSave()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .padding(.top, 10)
            }
        }
        .alert(item: $conflictAlert) { info in
            Alert(
                title: Text("Key already used"),
                message: Text("\"\(info.newKey.uppercased())\" is already assigned to \(displayName(info.existingTool)). Replace it?"),
                primaryButton: .destructive(Text("Replace")) {
                    hotkeys.removeValue(forKey: info.existingTool)
                    hotkeys[info.newTool] = info.newKey
                    onSave()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func toolRow(raw: String, name: String) -> some View {
        let isRecording = recordingTool == raw
        let currentKey = hotkeys[raw]
        return HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 2)
            Button {
                if isRecording {
                    EditorKeyCapture.cancelActive()
                } else {
                    recordingTool = raw
                    EditorKeyCapture.begin { key in
                        recordingTool = nil
                        guard let key else { return }
                        // Conflict check
                        if let conflict = hotkeys.first(where: { $0.value == key && $0.key != raw }) {
                            conflictAlert = ConflictInfo(newTool: raw, newKey: key, existingTool: conflict.key)
                        } else {
                            hotkeys[raw] = key
                            onSave()
                        }
                    }
                }
            } label: {
                Text(isRecording ? "…" : (currentKey?.uppercased() ?? "–"))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(isRecording ? .white : (currentKey == nil ? .secondary.opacity(0.5) : .secondary))
                    .frame(minWidth: 26)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(isRecording ? Color.accentColor : Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .handCursorOnHover()

            if currentKey != nil && !isRecording {
                Button {
                    hotkeys.removeValue(forKey: raw)
                    onSave()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(isRecording ? Color.accentColor.opacity(0.07) : Color.secondary.opacity(0.05)))
    }

    private func displayName(_ raw: String) -> String {
        toolRows.first(where: { $0.0 == raw })?.1 ?? raw
    }
}

// MARK: - EditorKeyCapture

/// Captures a single key press (with optional ⇧) for editor tool rebinding.
private final class EditorKeyCapture {
    private static var active: EditorKeyCapture?
    private var monitor: Any?
    private let completion: (String?) -> Void

    private init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    static func begin(completion: @escaping (String?) -> Void) {
        cancelActive()
        let capture = EditorKeyCapture(completion: completion)
        active = capture
        capture.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { capture.finish(nil); return nil }  // Esc → cancel
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let char = event.charactersIgnoringModifiers?.lowercased(), !char.isEmpty else {
                return nil
            }
            // Only accept alphanumeric, digits, and a few symbols; reject modifiers-only
            let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-=[];',./\\`"))
            guard char.unicodeScalars.allSatisfy({ validChars.contains($0) }) else { return nil }
            let key = mods == .shift ? "⇧\(char)" : char
            capture.finish(key)
            return nil
        }
    }

    static func cancelActive() { active?.finish(nil) }

    private func finish(_ key: String?) {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if EditorKeyCapture.active === self { EditorKeyCapture.active = nil }
        completion(key)
    }
}
