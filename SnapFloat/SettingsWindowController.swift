import AppKit

/// Settings window for SnapFloat preferences.
final class SettingsWindowController: NSWindowController {

    private static var instance: SettingsWindowController?

    private let settings = SettingsManager.shared

    private var durationSlider: NSSlider!
    private var durationLabel: NSTextField!
    private var autoSaveCheck: NSButton!
    private var pathLabel: NSTextField!
    private var browseButton: NSButton!

    // MARK: – Public

    static func show() {
        if let existing = instance {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = SettingsWindowController()
        instance = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: – Init

    init() {
        let winWidth: CGFloat = 460
        let winHeight: CGFloat = 220

        let screen = NSScreen.main!
        let origin = NSPoint(
            x: (screen.visibleFrame.width  - winWidth)  / 2 + screen.visibleFrame.minX,
            y: (screen.visibleFrame.height - winHeight) / 2 + screen.visibleFrame.minY
        )

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: winWidth, height: winHeight)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "SnapFloat — Ajustes"
        win.isReleasedWhenClosed = false

        super.init(window: win)
        win.delegate = self

        guard let content = win.contentView else { return }
        buildUI(in: content)
        loadCurrentValues()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: – UI

    private func buildUI(in parent: NSView) {
        let m: CGFloat = 20  // margin
        var y = parent.bounds.height - m

        // ── Preview duration ──
        y -= 20
        let sectionLabel1 = makeLabel("Duración de la vista previa:", bold: true)
        sectionLabel1.frame.origin = NSPoint(x: m, y: y)
        parent.addSubview(sectionLabel1)

        y -= 30
        durationSlider = NSSlider(value: 5, minValue: 1, maxValue: 30, target: self, action: #selector(sliderChanged))
        durationSlider.frame = NSRect(x: m, y: y, width: 300, height: 20)
        durationSlider.numberOfTickMarks = 0
        durationSlider.isContinuous = true
        parent.addSubview(durationSlider)

        durationLabel = makeLabel("5 s")
        durationLabel.frame = NSRect(x: m + 310, y: y, width: 60, height: 20)
        durationLabel.alignment = .left
        parent.addSubview(durationLabel)

        // ── Save location ──
        y -= 40
        let sectionLabel2 = makeLabel("Guardar capturas en disco:", bold: true)
        sectionLabel2.frame.origin = NSPoint(x: m, y: y)
        parent.addSubview(sectionLabel2)

        y -= 28
        autoSaveCheck = NSButton(checkboxWithTitle: "Guardar automáticamente", target: self, action: #selector(autoSaveToggled))
        autoSaveCheck.frame.origin = NSPoint(x: m, y: y)
        parent.addSubview(autoSaveCheck)

        y -= 30
        pathLabel = makeLabel("Sin carpeta seleccionada")
        pathLabel.frame = NSRect(x: m, y: y + 2, width: 300, height: 18)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        parent.addSubview(pathLabel)

        browseButton = NSButton(title: "Seleccionar…", target: self, action: #selector(browseTapped))
        browseButton.bezelStyle = .rounded
        browseButton.frame = NSRect(x: m + 310, y: y - 2, width: 110, height: 24)
        parent.addSubview(browseButton)
    }

    private func makeLabel(_ text: String, bold: Bool = false) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = bold ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 12)
        lbl.sizeToFit()
        return lbl
    }

    // MARK: – Load / save

    private func loadCurrentValues() {
        durationSlider.doubleValue = settings.previewDuration
        updateDurationLabel()

        autoSaveCheck.state = settings.autoSaveEnabled ? .on : .off
        updatePathUI()
    }

    private func updateDurationLabel() {
        let v = Int(durationSlider.doubleValue)
        durationLabel.stringValue = "\(v) s"
    }

    private func updatePathUI() {
        let enabled = autoSaveCheck.state == .on
        browseButton.isEnabled = enabled
        if enabled, let path = settings.saveLocation, !path.isEmpty {
            pathLabel.stringValue = path
            pathLabel.textColor = .labelColor
        } else {
            pathLabel.stringValue = enabled ? "Sin carpeta seleccionada" : "Desactivado"
            pathLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: – Actions

    @objc private func sliderChanged() {
        let rounded = round(durationSlider.doubleValue)
        durationSlider.doubleValue = rounded
        settings.previewDuration = rounded
        updateDurationLabel()
    }

    @objc private func autoSaveToggled() {
        settings.autoSaveEnabled = autoSaveCheck.state == .on
        updatePathUI()
    }

    @objc private func browseTapped() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Seleccionar"

        if let current = settings.saveLocation, !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current)
        }

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.settings.saveLocation = url.path
            self.updatePathUI()
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.instance = nil
    }
}
