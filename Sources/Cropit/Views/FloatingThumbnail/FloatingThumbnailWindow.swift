import Cocoa
import SwiftUI

struct ThumbnailEntry {
    let id: UUID
    let image: NSImage
    let date: Date
}

final class FloatingThumbnailWindow: NSWindow {
    var onSave: ((NSImage) -> Void)?
    var onEdit: ((NSImage) -> Void)?
    var onDiscard: ((NSImage) -> Void)?
    var onCopy: ((NSImage) -> Void)?
    var onReveal: ((NSImage) -> Void)?
    var onPin: ((NSImage) -> Void)?
    var onAutoSave: ((NSImage) -> Void)?

    private var entries: [ThumbnailEntry] = []
    private var currentIndex = 0
    private var autoDismissWork: DispatchWorkItem?
    private var autoDismissDelay: TimeInterval

    init(autoDismissDelay: TimeInterval = 5) {
        self.autoDismissDelay = autoDismissDelay
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let startSize = CGSize(width: 240, height: 160)
        let margin: CGFloat = 20
        let origin = CGPoint(x: screen.frame.maxX - startSize.width - margin, y: screen.frame.minY + margin)

        super.init(
            contentRect: NSRect(origin: origin, size: startSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self
    }

    // MARK: - Public API

    func pushEntry(image: NSImage) {
        autoDismissWork?.cancel()
        let entry = ThumbnailEntry(id: UUID(), image: image, date: Date())
        entries.insert(entry, at: 0)
        // Cap at 10
        if entries.count > 10 {
            entries = Array(entries.prefix(10))
        }
        currentIndex = 0
        rebuildView()
        show()
        scheduleAutoDismiss()
    }

    func navigate(by delta: Int) {
        let newIndex = currentIndex + delta
        guard newIndex >= 0 && newIndex < entries.count else { return }
        currentIndex = newIndex
        autoDismissWork?.cancel()
        rebuildView()
        scheduleAutoDismiss()
    }

    var currentImage: NSImage? {
        guard currentIndex >= 0 && currentIndex < entries.count else { return nil }
        return entries[currentIndex].image
    }

    // MARK: - View

    private func rebuildView() {
        guard currentIndex >= 0 && currentIndex < entries.count else {
            contentView = nil
            return
        }
        let entry = entries[currentIndex]
        let view = FloatingThumbnailView(
            image: entry.image,
            index: currentIndex,
            count: entries.count,
            onAction: { [weak self] action in
                self?.handleAction(action)
            },
            onNavigate: { [weak self] delta in
                self?.navigate(by: delta)
            }
        )
        contentView = NSHostingView(rootView: view)
        // Resize window to fit content
        sizingToFit()
    }

    private func sizingToFit() {
        guard let cv = contentView else { return }
        let fitting = cv.fittingSize
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        var frame = self.frame
        // Keep the bottom-left corner anchored
        let oldBottomLeft = CGPoint(x: frame.minX, y: frame.minY)
        frame.size = fitting
        frame.origin = CGPoint(
            x: min(oldBottomLeft.x, sf.maxX - fitting.width - 10),
            y: min(oldBottomLeft.y, sf.maxY - fitting.height - 10)
        )
        frame.origin.x = max(frame.origin.x, sf.minX + 10)
        frame.origin.y = max(frame.origin.y, sf.minY + 10)
        setFrame(frame, display: true, animate: true)
    }

    // MARK: - Actions

    private func handleAction(_ action: ThumbnailAction) {
        guard let image = currentImage else { return }
        autoDismissWork?.cancel()
        switch action {
        case .save:   onSave?(image)
        case .edit:   onEdit?(image)
        case .discard:
            entries.remove(at: currentIndex)
            if entries.isEmpty { close(); return }
            if currentIndex >= entries.count { currentIndex = entries.count - 1 }
            rebuildView()
            show()
            scheduleAutoDismiss()
        case .copy:   onCopy?(image)
        case .reveal: onReveal?(image)
        case .pin:    onPin?(image)
        }
    }

    // MARK: - Auto Dismiss

    private func scheduleAutoDismiss() {
        guard autoDismissDelay > 0 else { return }
        autoDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let image = self.currentImage else { return }
            self.onAutoSave?(image)
            self.fadeOutAndClose()
        }
        autoDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissDelay, execute: work)
    }

    func show() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1.0)
            animator().alphaValue = 1
        }
    }

    private func fadeOutAndClose() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().alphaValue = 0
        } completionHandler: { self.close() }
    }

    deinit {
        autoDismissWork?.cancel()
    }
}

// MARK: - NSWindowDelegate

extension FloatingThumbnailWindow: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // Optionally fade out when losing focus — but we keep it visible like CleanShot
    }
}
