import Cocoa
import SwiftUI

final class EditorWindow: NSWindow {
    init(image: NSImage) {
        let size = NSSize(width: 800, height: 600)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Annotate"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 400, height: 300)
        contentView = NSHostingView(rootView: EditorView(image: image, window: self))
        setFrameAutosaveName("EditorWindow")
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
