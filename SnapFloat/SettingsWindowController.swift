import AppKit
import Carbon

/// Settings window for SnapFloat preferences.
final class SettingsWindowController: NSWindowController {

    private static var instance: SettingsWindowController?

    private let settings = SettingsManager.shared

    private var shortcutRecorder: ShortcutRecorderView!
    private var shortcutSaveButton: NSButton!
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
        let winHeight: CGFloat = 414

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

        // ── Shortcut ──
        y -= 20
        addSection("Shortcut:", at: m, y: y, in: parent)

        y -= 28
        shortcutRecorder = ShortcutRecorderView(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers,
            frame: NSRect(x: m, y: y, width: 200, height: 24)
        )
        shortcutRecorder.onShortcutChanged = { [weak self] keyCode, mods in
            self?.settings.setHotkey(keyCode: keyCode, modifiers: mods)
        }
        shortcutRecorder.onPendingStateChanged = { [weak self] hasPending in
            self?.shortcutSaveButton.isHidden = !hasPending
        }
        parent.addSubview(shortcutRecorder)

        shortcutSaveButton = NSButton(title: "Save", target: self, action: #selector(saveShortcut))
        shortcutSaveButton.bezelStyle = .rounded
        shortcutSaveButton.frame = NSRect(x: m + 210, y: y - 1, width: 70, height: 26)
        shortcutSaveButton.isHidden = true
        parent.addSubview(shortcutSaveButton)

        // ── On capture ──
        y -= 40
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

    @objc private func saveShortcut() {
        shortcutRecorder.confirmPending()
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.instance = nil
    }
}

// MARK: – Shortcut recorder

/// Listens for key presses via a local event monitor.
/// Auto-saves when the combination reaches 3 components (modifiers + key).
/// Shows a Save button (via callback) when fewer than 3 components are recorded.
/// Click to start recording. Escape cancels. Click again to restart.
final class ShortcutRecorderView: NSView {
    private(set) var keyCode: UInt32
    private(set) var modifiers: UInt32
    var onShortcutChanged: ((UInt32, UInt32) -> Void)?
    var onPendingStateChanged: ((Bool) -> Void)?

    private var isRecording = false
    private var hasPendingCombo = false
    private var pendingKeyCode: UInt32 = 0
    private var pendingModifiers: UInt32 = 0

    private let label = NSTextField(labelWithString: "")
    private var localMonitor: Any?

    init(keyCode: UInt32, modifiers: UInt32, frame: NSRect) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.frame = bounds.insetBy(dx: 4, dy: 2)
        label.autoresizingMask = [.width, .height]
        addSubview(label)

        updateDisplay()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // MARK: – Recording lifecycle

    private func startRecording() {
        isRecording = true
        hasPendingCombo = false
        pendingKeyCode = 0
        pendingModifiers = 0

        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
        label.stringValue = "Press shortcut…"
        label.textColor = .secondaryLabelColor
        onPendingStateChanged?(false)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }

            if event.type == .flagsChanged {
                guard !self.hasPendingCombo else { return nil }
                let mods = HotkeyManager.carbonModifiers(from: event.modifierFlags)
                self.pendingModifiers = mods
                if mods != 0 {
                    self.label.stringValue = HotkeyManager.modifiersString(for: mods) + "…"
                    self.label.textColor = .secondaryLabelColor
                } else {
                    self.label.stringValue = "Press shortcut…"
                    self.label.textColor = .secondaryLabelColor
                }
                return nil
            }

            if event.type == .keyDown {
                if event.keyCode == 0x35 {
                    self.stopRecording()
                    return nil
                }

                let mods = HotkeyManager.carbonModifiers(from: event.modifierFlags)
                self.pendingKeyCode = UInt32(event.keyCode)
                self.pendingModifiers = mods
                self.hasPendingCombo = true

                self.label.stringValue = HotkeyManager.displayString(
                    forKeyCode: self.pendingKeyCode, modifiers: mods)
                self.label.textColor = .labelColor

                if self.componentCount(modifiers: mods) >= 3 {
                    self.confirmPending()
                } else {
                    self.onPendingStateChanged?(true)
                }
                return nil
            }

            return event
        }
    }

    func stopRecording() {
        isRecording = false
        hasPendingCombo = false
        removeMonitor()
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        updateDisplay()
        onPendingStateChanged?(false)
    }

    func confirmPending() {
        guard hasPendingCombo else { return }
        keyCode = pendingKeyCode
        modifiers = pendingModifiers
        onShortcutChanged?(keyCode, modifiers)
        stopRecording()
    }

    // MARK: – Helpers

    /// Total components: each modifier flag counts as 1, the key counts as 1.
    private func componentCount(modifiers: UInt32) -> Int {
        var c = 1
        if modifiers & UInt32(cmdKey)     != 0 { c += 1 }
        if modifiers & UInt32(shiftKey)   != 0 { c += 1 }
        if modifiers & UInt32(optionKey)  != 0 { c += 1 }
        if modifiers & UInt32(controlKey) != 0 { c += 1 }
        return c
    }

    private func updateDisplay() {
        label.stringValue = HotkeyManager.displayString(forKeyCode: keyCode, modifiers: modifiers)
        label.textColor = .labelColor
    }

    private func removeMonitor() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    deinit { removeMonitor() }
}
