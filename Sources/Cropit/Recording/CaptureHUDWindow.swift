import Cocoa
import SwiftUI
import Combine

final class HUDState: ObservableObject {
    @Published var displayText: String = ""
    var onStop: (() -> Void)?
    private var timer: Timer?
    private var statusProvider: (() -> String)?
    private var cancellable: AnyCancellable?

    init(updateInterval: TimeInterval = 0.1) {
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self, let provider = self.statusProvider else { return }
            let text = provider()
            if text != self.displayText {
                self.displayText = text
            }
        }
    }

    func setStatusProvider(_ provider: @escaping () -> String) {
        statusProvider = provider
        displayText = provider()
    }

    deinit { timer?.invalidate() }
}

final class CaptureHUDWindow: NSWindow {
    private let hostingView: NSHostingView<CaptureHUDContentView>
    private let hudState: HUDState

    init(statusProvider: @escaping () -> String, onStop: @escaping () -> Void) {
        let state = HUDState()
        state.setStatusProvider(statusProvider)
        state.onStop = onStop
        self.hudState = state

        let size = NSSize(width: 200, height: 44)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - 80)

        hostingView = NSHostingView(rootView: CaptureHUDContentView(state: state))

        super.init(
            contentRect: NSRect(origin: origin, size: size),
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

        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    func show() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().alphaValue = 1
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct CaptureHUDContentView: View {
    @ObservedObject var state: HUDState

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)

            Text(state.displayText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(minWidth: 70, alignment: .trailing)

            Button(action: { state.onStop?() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.8))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}
