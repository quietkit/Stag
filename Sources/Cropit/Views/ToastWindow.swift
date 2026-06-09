import Cocoa
import SwiftUI

/// Lightweight auto-dismissing notification pill — no interaction required.
/// Call `ToastWindow.show(...)` from any thread; it marshals to main automatically.
final class ToastWindow: NSWindow {

    // MARK: - Public API

    static func show(
        _ message: String,
        icon: String = "checkmark.circle.fill",
        iconColor: Color = .green,
        duration: TimeInterval = 2.5
    ) {
        DispatchQueue.main.async {
            let win = ToastWindow(message: message, icon: icon, iconColor: iconColor)
            win.popup(duration: duration)
        }
    }

    // MARK: - Private

    private init(message: String, icon: String, iconColor: Color) {
        let view = ToastView(message: message, icon: icon, iconColor: iconColor)
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize

        let screen  = NSScreen.main ?? NSScreen.screens[0]
        let vf      = screen.visibleFrame
        let origin  = CGPoint(x: vf.midX - size.width / 2,
                              y: vf.maxY - size.height - 12)

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask:   [.borderless, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        isOpaque              = false
        backgroundColor       = .clear
        hasShadow             = false
        level                 = .floating
        isReleasedWhenClosed  = false
        ignoresMouseEvents    = true
        collectionBehavior    = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        hosting.frame = NSRect(origin: .zero, size: size)
        contentView   = hosting
    }

    private func popup(duration: TimeInterval) {
        alphaValue = 0
        orderFrontRegardless()

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().alphaValue = 1
        }

        // Fade out after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0
            } completionHandler: {
                self.close()
            }
        }
    }
}

// MARK: - SwiftUI View

private struct ToastView: View {
    let message: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(iconColor)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        .padding(4) // keep shadow from clipping
    }
}
