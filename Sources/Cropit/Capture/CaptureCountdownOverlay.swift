import Cocoa

final class CaptureCountdownOverlay: NSWindow {
    private let countdownView: CountdownView

    override var canBecomeKey: Bool { false }

    init(count: Int = 3) {
        let screenFrame = NSScreen.main?.frame ?? .zero
        countdownView = CountdownView(count: count)

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.15)
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        countdownView.frame = NSRect(origin: .zero, size: screenFrame.size)
        countdownView.autoresizingMask = [.width, .height]
        contentView = countdownView
    }

    func start() async -> Bool {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return await countdownView.start()
    }

    override func close() {
        countdownView.stop()
        super.close()
    }
}

private final class CountdownView: NSView {
    private let count: Int
    private var current: Int
    private var timer: Timer?
    private var cancelled = false
    private var continuation: CheckedContinuation<Bool, Never>?

    init(count: Int) {
        self.count = max(1, count)
        self.current = max(1, count)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    func start() async -> Bool {
        cancelled = false
        current = count
        needsDisplay = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.current -= 1
            self.needsDisplay = true
            if self.current <= 0 {
                self.stop()
                self.continuation?.resume(returning: !self.cancelled)
                self.continuation = nil
            }
        }

        return await withCheckedContinuation { c in
            self.continuation = c
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func cancel() {
        cancelled = true
        stop()
        continuation?.resume(returning: false)
        continuation = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.08))
        ctx.fill(dirtyRect)

        guard current > 0 else { return }

        let text = "\(current)"
        let fontSize: CGFloat = 120
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let point = CGPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attrs)
    }
}
