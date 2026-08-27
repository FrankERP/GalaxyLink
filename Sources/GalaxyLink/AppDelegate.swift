import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = StreamController()
    private var pairingPanel: PairingPanelController?
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
        controller.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                FirstRun.markCompleteIfRunning(status)
                self?.rebuildMenu()
            }
        }
        controller.startServers()
        pairingPanel = PairingPanelController(
            onUseCable: { [weak self] in self?.enableUSB() },
            onStart: { [weak self] in self?.startStreaming() }
        )
        rebuildMenu()

        if FirstRun.shouldShowPairing() {
            pairingPanel?.present()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let streaming = controller.isStreaming

        let statusLine = menu.addItem(withTitle: MenuCopy.statusLine(isOn: streaming),
                                      action: nil, keyEquivalent: "")
        statusLine.isEnabled = false

        if case .failed(let message) = controller.status {
            let fail = menu.addItem(withTitle: message, action: nil, keyEquivalent: "")
            fail.isEnabled = false
        }

        if streaming {
            menu.addItem(withTitle: MenuCopy.stop, action: #selector(stopStreaming), keyEquivalent: "x")
        } else {
            menu.addItem(withTitle: MenuCopy.start, action: #selector(startStreaming), keyEquivalent: "s")
        }
        menu.addItem(withTitle: MenuCopy.showPairing, action: #selector(showPairing), keyEquivalent: "p")

        menu.addItem(.separator())
        let presetMenu = NSMenu()
        for preset in DisplayPreset.all {
            let item = NSMenuItem()
            item.attributedTitle = Self.presetAttributedTitle(preset)
            item.action = #selector(selectPreset(_:))
            item.representedObject = preset.name
            item.state = preset == currentPreset ? .on : .off
            item.target = self
            presetMenu.addItem(item)
        }
        let presetItem = menu.addItem(withTitle: MenuCopy.presetParentTitle(currentPreset), action: nil, keyEquivalent: "")
        menu.setSubmenu(presetMenu, for: presetItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: MenuCopy.useACable, action: #selector(enableUSB), keyEquivalent: "u")

        menu.addItem(.separator())
        menu.addItem(withTitle: MenuCopy.quit, action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.target ?? self }
        statusItem.menu = menu
    }

    private static func presetAttributedTitle(_ preset: DisplayPreset) -> NSAttributedString {
        var name = preset.menuTitle
        if preset == .default { name += " (default)" }
        let title = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ])
        title.append(NSAttributedString(string: "\n\(preset.footnote)", attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return title
    }

    @objc private func startStreaming() { controller.start(preset: currentPreset) }
    @objc private func stopStreaming() { controller.stop() }

    @objc private func showPairing() {
        pairingPanel?.present()
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let preset = DisplayPreset.all.first(where: { $0.name == name }) else { return }
        currentPreset = preset
        if controller.isStreaming { controller.start(preset: preset) }
        rebuildMenu()
    }

    @objc private func enableUSB() {
        let result = USBHelper.enableUSBMode()
        if CableAlert.presentsAlert(for: result) {
            pairingPanel?.showCableReady(false)
            let content = CableAlert.content(for: result)
            let alert = NSAlert()
            alert.messageText = content.message
            if let detail = content.detail {
                alert.informativeText = detail
            }
            alert.runModal()
            return
        }
        pairingPanel?.showCableReady()
        if pairingPanel?.window?.isVisible != true {
            pairingPanel?.present()
        }
    }

    @objc private func quit() {
        controller.shutdown()
        NSApp.terminate(nil)
    }
}
