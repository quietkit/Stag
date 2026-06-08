import Cocoa
import SwiftUI

final class CropitAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let captureManager: CaptureManager
    private var hotKeyObserver: Any?

    override init() {
        self.captureManager = CaptureManager(store: AppStore.shared)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        registerHotKey()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Capture")
        statusItem.button?.action = #selector(captureAction)
        statusItem.button?.target = self

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "5"))
        menu.addItem(NSMenuItem(title: "Capture Window", action: #selector(captureWindow), keyEquivalent: "4"))
        menu.addItem(NSMenuItem(title: "Capture Fullscreen", action: #selector(captureFullscreen), keyEquivalent: "3"))
        menu.addItem(NSMenuItem.separator())

        let recordMenu = NSMenu()
        recordMenu.addItem(NSMenuItem(title: "Record Screen", action: #selector(captureRecording), keyEquivalent: "6"))
        recordMenu.addItem(NSMenuItem(title: "Record GIF", action: #selector(captureGIF), keyEquivalent: "7"))
        let recordItem = NSMenuItem(title: "Record", action: nil, keyEquivalent: "")
        recordItem.submenu = recordMenu
        menu.addItem(recordItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Cropit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func registerHotKey() {
        hotKeyObserver = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let hotkeys = AppStore.shared.preferences.hotkeys
            let pressedMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            for (type, combo) in hotkeys {
                guard event.keyCode == combo.keyCode else { continue }
                guard pressedMods == combo.modifierFlags else { continue }
                Task { @MainActor in
                    self?.captureManager.startCapture(type: type)
                }
                return
            }
        }
    }

    @MainActor
    @objc private func captureArea() { captureManager.startCapture(type: .area) }

    @MainActor
    @objc private func captureWindow() { captureManager.startCapture(type: .window) }

    @MainActor
    @objc private func captureFullscreen() { captureManager.startCapture(type: .fullscreen) }

    @MainActor
    @objc private func captureRecording() { captureManager.startCapture(type: .recording) }

    @MainActor
    @objc private func captureGIF() { captureManager.startCapture(type: .gif) }

    @MainActor
    @objc private func captureAction() { captureManager.startCapture(type: .area) }

    @objc private func openSettings() { AppStore.shared.preferences.save() }
}
