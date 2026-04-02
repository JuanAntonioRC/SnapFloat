import AppKit

/// Settings window for SnapFloat preferences.
final class SettingsWindowController: NSWindowController {

    private static var instance: SettingsWindowController?

    private let settings = SettingsManager.shared

    private var durationSlider: NSSlider!
    private var durationLabel: NSTextField!
    private var capturePopup: NSPopUpButton!
    private var autoSaveCheck: NSButton!
    private var pathLabel: NSTextField!
    private var browseButton: NSButton!
    private var launchCheck: NSButton!

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
        let winHeight: CGFloat = 340

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
        win.title = "SnapFloat — Settings"
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
        let m: CGFloat = 20
        let fieldW: CGFloat = 300
        var y = parent.bounds.height - m

        // ── On capture ──
        y -= 20
        addSection("On capture:", at: m, y: y, in: parent)

        y -= 28
        capturePopup = NSPopUpButton(frame: NSRect(x: m, y: y, width: fieldW, height: 24), pullsDown: false)
        capturePopup.addItems(withTitles: [
            "Copy to clipboard",
            "Do nothing",
            "Save to folder",
            "Copy to clipboard & save to folder"
        ])
        capturePopup.target = self
        capturePopup.action = #selector(captureActionChanged)
        parent.addSubview(capturePopup)

        // ── Preview duration ──
        y -= 40
        addSection("Preview duration:", at: m, y: y, in: parent)

        y -= 30
        durationSlider = NSSlider(value: 5, minValue: 1, maxValue: 30, target: self, action: #selector(sliderChanged))
        durationSlider.frame = NSRect(x: m, y: y, width: fieldW, height: 20)
        durationSlider.isContinuous = true
        parent.addSubview(durationSlider)

        durationLabel = makeLabel("5 s")
        durationLabel.frame = NSRect(x: m + fieldW + 10, y: y, width: 60, height: 20)
        parent.addSubview(durationLabel)

        // ── Save location ──
        y -= 40
        addSection("Save location:", at: m, y: y, in: parent)

        y -= 28
        autoSaveCheck = NSButton(checkboxWithTitle: "Enable saving to disk", target: self, action: #selector(autoSaveToggled))
        autoSaveCheck.frame.origin = NSPoint(x: m, y: y)
        parent.addSubview(autoSaveCheck)

        y -= 30
        pathLabel = makeLabel("No folder selected")
        pathLabel.frame = NSRect(x: m, y: y + 2, width: fieldW, height: 18)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        parent.addSubview(pathLabel)

        browseButton = NSButton(title: "Choose…", target: self, action: #selector(browseTapped))
        browseButton.bezelStyle = .rounded
        browseButton.frame = NSRect(x: m + fieldW + 10, y: y - 2, width: 110, height: 24)
        parent.addSubview(browseButton)

        // ── General ──
        y -= 40
        addSection("General:", at: m, y: y, in: parent)

        y -= 28
        launchCheck = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(launchToggled))
        launchCheck.frame.origin = NSPoint(x: m, y: y)
        parent.addSubview(launchCheck)
    }

    private func addSection(_ title: String, at x: CGFloat, y: CGFloat, in parent: NSView) {
        let lbl = makeLabel(title, bold: true)
        lbl.frame.origin = NSPoint(x: x, y: y)
        parent.addSubview(lbl)
    }

    private func makeLabel(_ text: String, bold: Bool = false) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = bold ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 12)
        lbl.sizeToFit()
        return lbl
    }

    // MARK: – Load / save

    private func loadCurrentValues() {
        capturePopup.selectItem(at: settings.captureAction.rawValue)

        durationSlider.doubleValue = settings.previewDuration
        updateDurationLabel()

        autoSaveCheck.state = settings.autoSaveEnabled ? .on : .off
        updatePathUI()

        launchCheck.state = settings.launchAtLogin ? .on : .off
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
            pathLabel.stringValue = enabled ? "No folder selected" : "Disabled"
            pathLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: – Actions

    @objc private func captureActionChanged() {
        if let action = SettingsManager.CaptureAction(rawValue: capturePopup.indexOfSelectedItem) {
            settings.captureAction = action
        }
    }

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
        panel.prompt = "Choose"

        if let current = settings.saveLocation, !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current)
        }

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.settings.saveLocation = url.path
            self.updatePathUI()
        }
    }

    @objc private func launchToggled() {
        settings.launchAtLogin = launchCheck.state == .on
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.instance = nil
    }
}
