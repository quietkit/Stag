import Cocoa
import SwiftUI

final class PinboardWindow: NSWindow {
    var onClose: (() -> Void)?
    private let image: NSImage
    private var isLocked = false {
        didSet { ignoresMouseEvents = isLocked }
    }
    private var keyboardMonitor: Any?

    init(image: NSImage) {
        self.image = image
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
        let imgScale = min(400 / image.size.width, 300 / image.size.height, 1.0)
        let winSize = CGSize(
            width: image.size.width * imgScale,
            height: image.size.height * imgScale
        )
        let origin = CGPoint(
            x: (screenSize.width - winSize.width) / 2,
            y: (screenSize.height - winSize.height) / 2
        )

        super.init(
            contentRect: NSRect(origin: origin, size: winSize),
            styleMask: [.borderless, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        minSize = NSSize(width: 100, height: 80)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: PinboardView(
            image: image,
            onClose: { [weak self] in self?.closeAnimated() },
            onLockToggle: { [weak self] in self?.isLocked.toggle() },
            onOpacityChange: { [weak self] value in self?.alphaValue = value }
        ))
        setupKeyboardMonitor()
    }

    func show() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    private func closeAnimated() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self = self else { return }
            self.onClose?()
            self.close()
        }
    }

    // MARK: - Keyboard Nudge

    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isKeyWindow, !self.isLocked else { return event }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            var frame = self.frame
            switch event.keyCode {
            case 123: frame.origin.x -= step
            case 124: frame.origin.x += step
            case 125: frame.origin.y -= step
            case 126: frame.origin.y += step
            case 53:  self.closeAnimated(); return nil
            default:  return event
            }
            self.setFrame(frame, display: true)
            return nil
        }
    }
}

// MARK: - Pinboard View

struct PinboardView: View {
    let image: NSImage
    let onClose: () -> Void
    let onLockToggle: () -> Void
    let onOpacityChange: (Double) -> Void

    @State private var hovering = false
    @State private var isLocked = false
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            imageContent
            if hovering {
                controlsOverlay
            }
        }
        .onHover { hovering = $0 }
    }

    private var imageContent: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .allowsHitTesting(false)
    }

    private var controlsOverlay: some View {
        HStack(spacing: 6) {
            lockButton
            opacitySlider
            imageInfo
            closeButton
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(8)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    private var lockButton: some View {
        Button {
            isLocked.toggle()
            onLockToggle()
        } label: {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(isLocked ? Color.green.opacity(0.5) : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isLocked ? "Unlock" : "Lock")
    }

    private var opacitySlider: some View {
        Slider(value: $opacity, in: 0.2...1.0)
            .frame(width: 80)
            .controlSize(.mini)
            .onChange(of: opacity) { _, newValue in onOpacityChange(newValue) }
    }

    private var imageInfo: some View {
        Text("\(Int(image.size.width))×\(Int(image.size.height))")
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
    }

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.red.opacity(0.6))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
    }
}
