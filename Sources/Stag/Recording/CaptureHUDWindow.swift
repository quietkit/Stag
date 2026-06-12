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

    /// Pass `onStop: nil` to show a progress HUD with no stop button.
    init(statusProvider: @escaping () -> String, onStop: (() -> Void)? = nil) {
        let state = HUDState()
        state.setStatusProvider(statusProvider)
        state.onStop = onStop
        self.hudState = state

        let size = NSSize(width: 200, height: 44)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let origin = CGPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 8)

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
        ignoresMouseEvents = false   // must be false so the Stop button is clickable
        sharingType = .none          // exclude from screen capture / GIF output

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
            if state.onStop != nil {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
            } else {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 16, height: 16)
            }

            Text(state.displayText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(minWidth: 70, alignment: .trailing)

            if let stop = state.onStop {
                Button(action: stop) {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}
