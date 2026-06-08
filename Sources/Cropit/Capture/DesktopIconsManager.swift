import Cocoa

final class DesktopIconsManager {
    static let shared = DesktopIconsManager()
    private var hidden = false
    private var originalValue: String?

    private init() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.finder", "CreateDesktop"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        originalValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hide() {
        guard !hidden else { return }
        setDesktopIcons(enabled: false)
        hidden = true
    }

    func show() {
        guard hidden else { return }
        setDesktopIcons(enabled: true)
        hidden = false
    }

    func restore() {
        if hidden { show() }
    }

    private func setDesktopIcons(enabled: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", enabled ? "true" : "false"]
        try? task.run()
        task.waitUntilExit()

        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killTask.arguments = ["Finder"]
        try? killTask.run()
        killTask.waitUntilExit()
    }
}
