import Cocoa
import os

struct MouseClickEvent: Equatable {
    let position: CGPoint
    let button: Int
    let timestamp: Date
    let duration: TimeInterval

    var age: TimeInterval { Date().timeIntervalSince(timestamp) }

    var alpha: CGFloat {
        let a = 1.0 - (age / duration)
        return max(0, min(1, a))
    }

    var radius: CGFloat {
        let progress = age / duration
        return 10 + progress * 30
    }

    var isExpired: Bool { age >= duration }
}

final class MouseClickManager {
    static let shared = MouseClickManager()

    private let logger = Logger(subsystem: "com.ganwar.Cropit", category: "MouseClick")
    private var monitor: Any?
    private var clickEvents: [MouseClickEvent] = []
    private let eventLock = NSLock()
    private let clickDuration: TimeInterval = 0.8
    private var isEnabled = false

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        clickEvents.removeAll()

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self = self else { return }
            let clickEvent = MouseClickEvent(
                position: NSEvent.mouseLocation,
                button: event.buttonNumber,
                timestamp: Date(),
                duration: self.clickDuration
            )
            self.eventLock.lock()
            self.clickEvents.append(clickEvent)
            if self.clickEvents.count > 50 {
                self.clickEvents.removeFirst(self.clickEvents.count - 50)
            }
            self.eventLock.unlock()
        }
    }

    func stop() {
        guard isEnabled else { return }
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isEnabled = false
        eventLock.lock()
        clickEvents.removeAll()
        eventLock.unlock()
    }

    func activeClicks(at timestamp: Date) -> [MouseClickEvent] {
        eventLock.lock()
        defer { eventLock.unlock() }
        clickEvents.removeAll { $0.isExpired }
        return clickEvents.filter { abs($0.timestamp.timeIntervalSince(timestamp)) < $0.duration }
    }

    func drawClickRipple(on cgContext: CGContext, at timestamp: Date) {
        let clicks = activeClicks(at: timestamp)
        for click in clicks {
            let pos = click.position
            let screenHeight = NSScreen.screens.first?.frame.height ?? 0
            let flippedY = screenHeight - pos.y

            let alpha = click.alpha
            let radius = click.radius

            cgContext.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(alpha).cgColor)
            cgContext.setLineWidth(2.5)
            cgContext.strokeEllipse(in: CGRect(x: pos.x - radius, y: flippedY - radius,
                                                width: radius * 2, height: radius * 2))

            cgContext.setFillColor(NSColor.controlAccentColor.withAlphaComponent(alpha * 0.25).cgColor)
            cgContext.fillEllipse(in: CGRect(x: pos.x - radius * 0.4, y: flippedY - radius * 0.4,
                                              width: radius * 0.8, height: radius * 0.8))

            cgContext.setFillColor(NSColor.white.withAlphaComponent(alpha * 0.5).cgColor)
            cgContext.fillEllipse(in: CGRect(x: pos.x - 2, y: flippedY - 2, width: 4, height: 4))
        }
    }
}
