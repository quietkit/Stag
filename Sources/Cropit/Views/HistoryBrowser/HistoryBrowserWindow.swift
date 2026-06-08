import Cocoa
import SwiftUI

final class HistoryBrowserWindow: NSWindow {
    private let hostingView: NSHostingView<HistoryBrowserView>

    init() {
        let size = NSSize(width: 720, height: 500)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )
        hostingView = NSHostingView(rootView: HistoryBrowserView())
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Capture History"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 500, height: 300)
        setFrameAutosaveName("HistoryBrowserWindow")
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
