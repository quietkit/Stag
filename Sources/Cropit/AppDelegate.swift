import Cocoa
import SwiftUI
import OSLog
import Carbon

final class CropitAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let captureManager: CaptureManager
    private var settingsWindow: PreferencesWindow?
    private var historyWindow: HistoryBrowserWindow?
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var permissionCheckTimer: Timer?
    private var carbonHotkeyRefs: [EventHotKeyRef] = []
    private var carbonEventHandler: EventHandlerRef?

    private let logger = Logger(subsystem: "com.ganwar.Cropit", category: "AppDelegate")

    override init() {
        self.captureManager = CaptureManager(store: AppStore.shared)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        installLocalMonitor()
        installCarbonHotkeys()   // works without Accessibility permission
        installEventTap()        // also install event tap if Accessibility is granted
        registerURLScheme()
        logger.info("Cropit launched successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionCheckTimer?.invalidate()
        uninstallCarbonHotkeys()
        uninstallMonitors()
        DesktopIconsManager.shared.restore()
        DNDManager.shared.restore()
    }

    // MARK: - Status Item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Cropit") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            statusItem.button?.image = img.withSymbolConfiguration(cfg)
        }
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showStatusMenu)
        statusItem.button?.toolTip = "Click for capture controls"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "5"))
        menu.addItem(NSMenuItem(title: "Capture Window", action: #selector(captureWindow), keyEquivalent: "4"))
        menu.addItem(NSMenuItem(title: "Capture Fullscreen", action: #selector(captureFullscreen), keyEquivalent: "3"))
        menu.addItem(NSMenuItem(title: "Scrolling Capture", action: #selector(captureScrolling), keyEquivalent: "2"))
        menu.addItem(NSMenuItem.separator())
        
        let recordMenu = NSMenu()
        recordMenu.addItem(NSMenuItem(title: "Record Screen", action: #selector(captureRecording), keyEquivalent: "6"))
        recordMenu.addItem(NSMenuItem(title: "Record GIF", action: #selector(captureGIF), keyEquivalent: "7"))
        let recordItem = NSMenuItem(title: "Record", action: nil, keyEquivalent: "")
        recordItem.submenu = recordMenu
        menu.addItem(recordItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Capture History", action: #selector(openHistory), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Cropit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }

    @objc private func showStatusMenu() {
        statusItem.button?.performClick(nil)
    }

    // MARK: - Local Monitor (works when app windows are active)

    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.dispatchIfHotkey(keyCode: event.keyCode, flags: event.modifierFlags) ? nil : event
        }
    }

    // MARK: - CGEvent Tap (system-wide, catches ALL keys with ⌘)

    private func installEventTap() {
        // If the user already has accessibility permission, try immediately.
        if AXIsProcessTrusted() {
            createEventTap()
            return
        }
        // No permission. If the user previously dismissed our prompt, stay silent —
        // don't attempt tapCreate (which triggers macOS's own folder-icon dialog).
        if UserDefaults.standard.bool(forKey: Self.accessibilityDismissedKey) {
            logger.info("Accessibility permission not granted; user previously dismissed prompt. Using local monitor only.")
            return
        }
        // First time: try to create the tap (it will fail without permission, but
        // the attempt is silent — macOS no longer auto-prompts for CGEvent taps),
        // then show our own friendly alert.
        createEventTap()
        if eventTap == nil {
            showAccessibilityAlert()
        }
    }

    private func createEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                let delegate = Unmanaged<CropitAppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                if delegate.dispatchIfHotkey(keyCode: UInt16(keyCode), flags: flags) {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        if let tap = tap {
            eventTap = tap
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            logger.info("Event tap installed successfully.")
        }
    }

    private static let accessibilityDismissedKey = "com.ganwar.Cropit.accessibilityAlertDismissed"

    private func showAccessibilityAlert() {
        // Don't nag: if the user already dismissed with "Later", respect that choice.
        if UserDefaults.standard.bool(forKey: Self.accessibilityDismissedKey) { return }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Cropit Needs Accessibility Access"
            alert.informativeText = "To use global keyboard shortcuts while you're in other apps, Cropit needs Accessibility permission.\n\nSystem Settings → Privacy & Security → Accessibility → add Cropit."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
                // Poll so we auto-activate the tap once the user grants it
                self.permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                    self?.retryEventTap()
                }
            } else {
                // User chose Later — remember so we never show again until they manually reset
                UserDefaults.standard.set(true, forKey: Self.accessibilityDismissedKey)
            }
        }
    }

    private func retryEventTap() {
        guard eventTap == nil else {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            return
        }
        guard AXIsProcessTrusted() else { return } // still no permission, wait
        createEventTap()
        if eventTap != nil {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }

    // MARK: - Carbon Hotkeys (no Accessibility permission required)

    private func installCarbonHotkeys() {
        uninstallCarbonHotkeys()

        // Install event handler for hotKey events
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, refcon -> OSStatus in
            guard let refcon = refcon else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<CropitAppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                delegate.handleCarbonHotkey(id: hotkeyID.id)
            }
            return noErr
        }, 1, &eventSpec, selfPtr, &carbonEventHandler)

        registerCarbonHotkeys()
    }

    private func registerCarbonHotkeys() {
        let hotkeys = AppStore.shared.preferences.hotkeys
        var id: UInt32 = 1
        for (captureType, combo) in hotkeys {
            var ref: EventHotKeyRef?
            let hotkeyID = EventHotKeyID(signature: OSType(0x4352_4F50), id: id)  // 'CROP'
            let carbonMods = carbonModifiers(from: combo.modifierFlags)
            let err = RegisterEventHotKey(UInt32(combo.keyCode), carbonMods,
                                          hotkeyID, GetApplicationEventTarget(),
                                          0, &ref)
            if err == noErr, let ref = ref {
                carbonHotkeyRefs.append(ref)
                carbonHotkeyTypeMap[id] = captureType
            }
            id += 1
        }
    }

    private var carbonHotkeyTypeMap: [UInt32: CaptureType] = [:]

    @MainActor
    private func handleCarbonHotkey(id: UInt32) {
        guard let captureType = carbonHotkeyTypeMap[id] else { return }
        captureManager.startCapture(type: captureType)
    }

    private func uninstallCarbonHotkeys() {
        for ref in carbonHotkeyRefs { UnregisterEventHotKey(ref) }
        carbonHotkeyRefs.removeAll()
        carbonHotkeyTypeMap.removeAll()
        if let handler = carbonEventHandler {
            RemoveEventHandler(handler)
            carbonEventHandler = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    private func uninstallMonitors() {
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // MARK: - Hotkey Dispatch

    private func dispatchIfHotkey(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let mods = flags.intersection(.deviceIndependentFlagsMask)
        let hotkeys = AppStore.shared.preferences.hotkeys
        for (type, combo) in hotkeys {
            guard keyCode == combo.keyCode else { continue }
            guard mods == combo.modifierFlags else { continue }
            DispatchQueue.main.async { [self] in
                NSApp.activate(ignoringOtherApps: true)
                self.captureManager.startCapture(type: type)
            }
return true
        }
        return false
    }

    // MARK: - URL Scheme

    private func registerURLScheme() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @MainActor
    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        handleURL(url)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    @MainActor
    private func handleURL(_ url: URL) {
        guard let cmd = URLSchemeHandler.parse(url) else { return }
        switch cmd {
        case .capture(let type, let delay):
            let captureType = type ?? .area
            if delay > 0 {
                AppStore.shared.preferences.captureDelay = delay
            }
            captureManager.startCapture(type: captureType)
        case .preferences:
            openSettings()
        case .history:
            openHistory()
        case .pinboard:
            break
        }
    }

    @MainActor
    @objc private func captureArea() { captureManager.startCapture(type: .area) }

    @MainActor
    @objc private func captureWindow() { captureManager.startCapture(type: .window) }

    @MainActor
    @objc private func captureFullscreen() { captureManager.startCapture(type: .fullscreen) }

    @MainActor
    @objc private func captureScrolling() { captureManager.startCapture(type: .scrolling) }

    @MainActor
    @objc private func captureRecording() { captureManager.startCapture(type: .recording) }

    @MainActor
    @objc private func captureGIF() { captureManager.startCapture(type: .gif) }

    @MainActor
    @objc private func captureAction() { captureManager.startCapture(type: .area) }

    @objc private func openHistory() {
        if historyWindow == nil {
            historyWindow = HistoryBrowserWindow()
        }
        historyWindow?.show()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = PreferencesWindow()
        }
        settingsWindow?.show()
    }
}