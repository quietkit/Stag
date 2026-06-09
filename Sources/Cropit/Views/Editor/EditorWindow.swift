import Cocoa
import SwiftUI

final class EditorWindow: NSWindow, NSWindowDelegate {
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
        delegate = self
        self.center()
    }

    func show() {
        WindowLifecycle.didOpen(self)
    }

    // ESC closes the editor without saving
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    func windowWillClose(_ notification: Notification) {
        WindowLifecycle.didClose(self)
    }
}
