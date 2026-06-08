import Cocoa
import os

final class DNDManager {
    static let shared = DNDManager()

    private let logger = Logger(subsystem: "com.ganwar.Cropit", category: "DND")
    private var wasEnabled = false
    private var isEnabled = false

    func enable() {
        guard !isEnabled else { return }
        wasEnabled = isDNDEnabled()
        setDND(true)
        isEnabled = true
        logger.notice("DND enabled")
    }

    func restore() {
        guard isEnabled else { return }
        if !wasEnabled {
            setDND(false)
        }
        isEnabled = false
        logger.notice("DND restored")
    }

    private func isDNDEnabled() -> Bool {
        let dnd = UserDefaults(suiteName: "com.apple.notificationcenterui")
        return dnd?.bool(forKey: "doNotDisturb") == true
    }

    private func setDND(_ on: Bool) {
        let dnd = UserDefaults(suiteName: "com.apple.notificationcenterui")
        dnd?.set(on, forKey: "doNotDisturb")
        dnd?.synchronize()

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.apple.notificationcenterui.dndprefs_changed"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
