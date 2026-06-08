import Cocoa
import SwiftUI

final class KeystrokeManager {
    static let shared = KeystrokeManager()

    private var window: KeystrokeWindow?
    private var keyMonitor: Any?
    private var isActive = false
    private var dismissWork: DispatchWorkItem?

    private init() {}

    func start() {
        guard !isActive else { return }
        isActive = true
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        window?.close()
        window = nil
        dismissWork?.cancel()
        dismissWork = nil
    }

    private func handleEvent(_ event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let text = self.formatKeystroke(event)
            guard !text.isEmpty else { return }
            self.showKeystroke(text)
        }
    }

    private func formatKeystroke(_ event: NSEvent) -> String {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var prefix = ""
        if mods.contains(.command)  { prefix += "\u{2318}" }
        if mods.contains(.shift)    { prefix += "\u{21E7}" }
        if mods.contains(.option)   { prefix += "\u{2325}" }
        if mods.contains(.control)  { prefix += "\u{2303}" }

        if event.type == .flagsChanged { return prefix.isEmpty ? "" : prefix }
        guard let chars = event.charactersIgnoringModifiers else { return prefix }
        let key = chars.uppercased()
        let special: [UInt16: String] = [
            36: "\u{23CE}",  // Return
            53: "\u{238B}",  // Esc
            48: "\u{21E5}",  // Tab
            49: "Space",
            51: "\u{232B}",  // Delete
            123: "\u{2190}", // Left
            124: "\u{2192}", // Right
            125: "\u{2193}", // Down
            126: "\u{2191}", // Up
            115: "\u{21DE}", // Home (actually Fn+Left)
            119: "\u{21DF}", // End (actually Fn+Right)
            116: "\u{21E1}", // Page Up
            121: "\u{21E3}", // Page Down
        ]
        let keyStr = special[event.keyCode] ?? key
        return prefix + keyStr
    }

    private func showKeystroke(_ text: String) {
        dismissWork?.cancel()

        if window == nil {
            let size = NSSize(width: 120, height: 40)
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 60)
            window = KeystrokeWindow(contentRect: NSRect(origin: origin, size: size))
            window?.show()
        }

        window?.setText(text)

        let work = DispatchWorkItem { [weak self] in
            self?.window?.close()
            self?.window = nil
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}

final class KeystrokeWindow: NSWindow {
    private let textView: NSHostingView<KeystrokeLabel>

    init(contentRect: NSRect) {
        textView = NSHostingView(rootView: KeystrokeLabel(text: ""))
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = true

        textView.frame = NSRect(origin: .zero, size: contentRect.size)
        textView.autoresizingMask = [.width, .height]
        contentView = textView
    }

    func show() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
    }

    func setText(_ text: String) {
        textView.rootView = KeystrokeLabel(text: text)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct KeystrokeLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.7))
            )
    }
}
