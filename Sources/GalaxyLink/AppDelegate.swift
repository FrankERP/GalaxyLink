import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = StreamController()
    private var currentPreset: DisplayPreset {
        get {
            let name = UserDefaults.standard.string(forKey: "preset.name")
            return DisplayPreset.all.first { $0.name == name } ?? .default
        }
        set { UserDefaults.standard.set(newValue.name, forKey: "preset.name") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⬒"
        statusItem.button?.toolTip = "GalaxyLink"
        controller.onStatusChange = { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        switch controller.status {
        case .stopped:
            menu.addItem(withTitle: "Status: stopped", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Start Streaming", action: #selector(startStreaming), keyEquivalent: "s")
        case .running(let url):
            menu.addItem(withTitle: "Status: streaming", action: nil, keyEquivalent: "")
            let urlItem = menu.addItem(withTitle: "On the tablet, open: \(url)  (click to copy)",
                                       action: #selector(copyURL(_:)), keyEquivalent: "c")
            urlItem.representedObject = url
            if let qr = QRCode.image(for: url) {
                let item = NSMenuItem()
                item.image = qr
                menu.addItem(item)
            }
            menu.addItem(withTitle: "Stop Streaming", action: #selector(stopStreaming), keyEquivalent: "x")
        case .failed(let message):
            menu.addItem(withTitle: "Failed: \(message)", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Start Streaming", action: #selector(startStreaming), keyEquivalent: "s")
        }

        menu.addItem(.separator())
        let presetMenu = NSMenu()
        for preset in DisplayPreset.all {
            let item = presetMenu.addItem(withTitle: preset.name, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.representedObject = preset.name
            item.state = preset == currentPreset ? .on : .off
            item.target = self
        }
        let presetItem = menu.addItem(withTitle: "Resolution", action: nil, keyEquivalent: "")
        menu.setSubmenu(presetMenu, for: presetItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Enable USB Mode (adb)", action: #selector(enableUSB), keyEquivalent: "u")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit GalaxyLink", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.target ?? self }
        statusItem.menu = menu
    }

    @objc private func startStreaming() { controller.start(preset: currentPreset) }
    @objc private func stopStreaming() { controller.stop() }

    @objc private func copyURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let preset = DisplayPreset.all.first(where: { $0.name == name }) else { return }
        currentPreset = preset
        if case .running = controller.status { controller.start(preset: preset) }
        rebuildMenu()
    }

    @objc private func enableUSB() {
        let alert = NSAlert()
        switch USBHelper.enableUSBMode() {
        case .success(let message):
            alert.messageText = "USB mode enabled"
            alert.informativeText = message
        case .failure(.adbNotFound):
            alert.messageText = "adb not found"
            alert.informativeText = "Install Android platform-tools (brew install android-platform-tools) and retry."
        case .failure(.noDevice):
            alert.messageText = "No tablet detected"
            alert.informativeText = "Connect the tablet via USB, enable USB debugging (Settings ▸ Developer options), accept the prompt on the tablet, and retry."
        case .failure(.commandFailed(let output)):
            alert.messageText = "adb reverse failed"
            alert.informativeText = output
        }
        alert.runModal()
    }

    @objc private func quit() {
        controller.stop()
        NSApp.terminate(nil)
    }
}
