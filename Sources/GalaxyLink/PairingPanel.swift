import AppKit

final class PairingPanelController: NSWindowController, NSWindowDelegate {
    private let onUseCable: () -> Void
    private let onStart: () -> Void

    private var headingLabel: NSTextField!
    private var openSettingsButton: NSButton!
    private var deniedStack: NSStackView!
    private var lineLabel: NSTextField!
    private var useCableButton: NSButton!
    private var usbURLButton: NSButton!
    private var cableReadyLabel: NSTextField!
    private var startButton: NSButton!
    private var wifiToggle: NSButton!
    private var wifiURLButton: NSButton!
    private var wifiDetail: NSStackView!
    private var outerStack: NSStackView!
    private var wifiExpanded = false
    private var cableIsReady = false
    private var copiedReset: DispatchWorkItem?

    init(onUseCable: @escaping () -> Void, onStart: @escaping () -> Void) {
        self.onUseCable = onUseCable
        self.onStart = onStart
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = PairingCopy.windowTitle
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        super.init(window: panel)
        panel.delegate = self
        panel.contentView = makeContent()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        wifiExpanded = false
        refresh()
        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    private func makeContent() -> NSView {
        let content = NSView()

        headingLabel = Self.label(PairingCopy.title, font: .systemFont(ofSize: 22, weight: .semibold))

        let deniedMessage = Self.label(PairingCopy.needsScreenRecording,
                                       font: .systemFont(ofSize: 15, weight: .medium))
        openSettingsButton = NSButton(title: PairingCopy.openSettings, target: self, action: #selector(openSettings))
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.controlSize = .large
        deniedStack = NSStackView(views: [deniedMessage, openSettingsButton])
        deniedStack.orientation = .vertical
        deniedStack.alignment = .centerX
        deniedStack.spacing = 12

        lineLabel = Self.label(PairingCopy.line, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        lineLabel.preferredMaxLayoutWidth = 340

        useCableButton = NSButton(title: PairingCopy.useACable, target: self, action: #selector(useCableTapped))
        useCableButton.bezelStyle = .rounded
        useCableButton.controlSize = .large

        usbURLButton = Self.copyableURLButton(title: Pairing.usbURL, target: self, action: #selector(copyUSBURL))

        cableReadyLabel = Self.label(PairingCopy.cableReady, font: .systemFont(ofSize: 13, weight: .medium))
        cableReadyLabel.isHidden = true

        startButton = NSButton(title: PairingCopy.start, target: self, action: #selector(startTapped))
        startButton.bezelStyle = .rounded
        startButton.controlSize = .large

        wifiToggle = NSButton(title: PairingCopy.sameWiFi, target: self, action: #selector(toggleWiFi))
        wifiToggle.isBordered = false
        wifiToggle.font = .systemFont(ofSize: 13)
        wifiToggle.contentTintColor = .secondaryLabelColor
        wifiToggle.imagePosition = .imageLeading
        wifiToggle.imageHugsTitle = true

        wifiURLButton = Self.copyableURLButton(title: "", target: self, action: #selector(copyWiFiURL))
        wifiDetail = NSStackView(views: [wifiURLButton])
        wifiDetail.orientation = .vertical
        wifiDetail.alignment = .centerX

        outerStack = NSStackView(views: [
            headingLabel, deniedStack, lineLabel, useCableButton, usbURLButton, cableReadyLabel, startButton, wifiToggle, wifiDetail,
        ])
        outerStack.orientation = .vertical
        outerStack.alignment = .centerX
        outerStack.spacing = 14
        outerStack.setCustomSpacing(20, after: headingLabel)
        outerStack.setCustomSpacing(18, after: deniedStack)
        outerStack.setCustomSpacing(8, after: usbURLButton)
        outerStack.setCustomSpacing(18, after: cableReadyLabel)
        outerStack.setCustomSpacing(22, after: startButton)
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            outerStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            outerStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            outerStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            outerStack.widthAnchor.constraint(equalToConstant: 352),
        ])
        return content
    }

    func refresh() {
        copiedReset?.cancel()
        usbURLButton.title = Pairing.usbURL
        wifiURLButton.title = Pairing.wifiURL()
        let granted = ScreenRecordingAccess.isGranted
        deniedStack.isHidden = granted
        if granted {
            useCableButton.keyEquivalent = "\r"
            openSettingsButton.keyEquivalent = ""
        } else {
            useCableButton.keyEquivalent = ""
            openSettingsButton.keyEquivalent = "\r"
        }
        wifiDetail.isHidden = !wifiExpanded
        cableReadyLabel.isHidden = !cableIsReady
        updateWiFiToggleImage()
        fitWindow()
    }

    func showCableReady(_ ready: Bool = true) {
        cableIsReady = ready
        cableReadyLabel.isHidden = !ready
        fitWindow()
    }

    private func fitWindow() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        var size = content.fittingSize
        size.width = max(400, size.width)
        window.setContentSize(size)
    }

    private func updateWiFiToggleImage() {
        let name = wifiExpanded ? "chevron.down" : "chevron.right"
        wifiToggle.image = NSImage(systemSymbolName: name, accessibilityDescription: PairingCopy.sameWiFi)
    }

    @objc private func useCableTapped() { onUseCable() }
    @objc private func startTapped() { onStart() }
    @objc private func openSettings() { ScreenRecordingAccess.openSystemSettings() }

    @objc private func toggleWiFi() {
        wifiExpanded.toggle()
        wifiDetail.isHidden = !wifiExpanded
        updateWiFiToggleImage()
        fitWindow()
    }

    @objc private func copyUSBURL() { copyToPasteboard(Pairing.usbURL, button: usbURLButton) }
    @objc private func copyWiFiURL() { copyToPasteboard(Pairing.wifiURL(), button: wifiURLButton) }

    private func copyToPasteboard(_ string: String, button: NSButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        button.title = "Copied"
        copiedReset?.cancel()
        let work = DispatchWorkItem { [weak self, weak button] in
            button?.title = string
            self?.copiedReset = nil
        }
        copiedReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private static func copyableURLButton(title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        button.contentTintColor = .linkColor
        button.toolTip = "Click to copy"
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    private static func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 4
        return field
    }
}
