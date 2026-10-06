import Cocoa

class SettingsWindowController: NSWindowController {
    private var hardBounceSlider: NSSlider!
    private var hardBounceLabel: NSTextField!
    private var softBounceSlider: NSSlider!
    private var softBounceLabel: NSTextField!
    private var enableFlashCheckbox: NSButton!
    private var eventsBlockedLabel: NSTextField!

    private weak var keyboardEngine: KeyboardEngine?
    private weak var appDelegate: AppDelegate?

    convenience init(keyboardEngine: KeyboardEngine?, appDelegate: AppDelegate?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Butterfly Settings"
        window.isReleasedWhenClosed = false // Keep window controller alive

        self.init(window: window)
        self.keyboardEngine = keyboardEngine
        self.appDelegate = appDelegate

        setupUI()
        loadSettings()
        window.center()
    }

    override func showWindow(_ sender: Any?) {
        updateStatsLabel()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 18
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let hard = makeSliderSection(
            title: "Hard Bounce Threshold",
            help: "Repeats of the same key faster than this are always blocked.",
            min: 10, max: 100,
            action: #selector(hardBounceChanged(_:))
        )
        stackView.addArrangedSubview(hard.section)
        hardBounceSlider = hard.slider
        hardBounceLabel = hard.label

        let soft = makeSliderSection(
            title: "Soft Bounce Threshold",
            help: "Repeats faster than this are blocked only if the doubled letter doesn't form a real word (e.g. \"thhe\").",
            min: 50, max: 200,
            action: #selector(softBounceChanged(_:))
        )
        stackView.addArrangedSubview(soft.section)
        softBounceSlider = soft.slider
        softBounceLabel = soft.label

        let flashCheckbox = NSButton(checkboxWithTitle: "Flash menu bar icon when a keystroke is blocked", target: self, action: #selector(flashCheckboxChanged(_:)))
        stackView.addArrangedSubview(flashCheckbox)
        enableFlashCheckbox = flashCheckbox

        // Stats row
        let statsRow = NSStackView()
        statsRow.orientation = .horizontal
        statsRow.spacing = 12

        let eventsLabel = NSTextField(labelWithString: "")
        statsRow.addArrangedSubview(eventsLabel)
        eventsBlockedLabel = eventsLabel

        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetStats(_:)))
        resetButton.controlSize = .small
        resetButton.bezelStyle = .rounded
        statsRow.addArrangedSubview(resetButton)

        stackView.addArrangedSubview(statsRow)

        // Restore defaults
        let defaultsButton = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults(_:)))
        defaultsButton.bezelStyle = .rounded
        stackView.addArrangedSubview(defaultsButton)

        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            hard.section.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            soft.section.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40)
        ])
    }

    private func makeSliderSection(title: String, help: String, min: Double, max: Double, action: Selector) -> (section: NSStackView, slider: NSSlider, label: NSTextField) {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        section.addArrangedSubview(titleLabel)

        let helpLabel = NSTextField(wrappingLabelWithString: help)
        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor
        section.addArrangedSubview(helpLabel)

        let controlRow = NSStackView()
        controlRow.orientation = .horizontal
        controlRow.spacing = 12

        let slider = NSSlider(value: min, minValue: min, maxValue: max, target: self, action: action)
        slider.isContinuous = true
        controlRow.addArrangedSubview(slider)

        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
        controlRow.addArrangedSubview(valueLabel)

        section.addArrangedSubview(controlRow)
        controlRow.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        helpLabel.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        return (section, slider, valueLabel)
    }

    private func loadSettings() {
        hardBounceSlider.doubleValue = (keyboardEngine?.hardBounceThreshold ?? 0.040) * 1000
        softBounceSlider.doubleValue = (keyboardEngine?.softBounceThreshold ?? 0.100) * 1000
        updateSliderLabels()

        enableFlashCheckbox.state = (appDelegate?.flashEnabled ?? true) ? .on : .off
        updateStatsLabel()
    }

    private func updateSliderLabels() {
        hardBounceLabel.stringValue = String(format: "%.0f ms", hardBounceSlider.doubleValue)
        softBounceLabel.stringValue = String(format: "%.0f ms", softBounceSlider.doubleValue)
    }

    @objc private func hardBounceChanged(_ sender: NSSlider) {
        // The soft window must start at or after the hard window
        if softBounceSlider.doubleValue < sender.doubleValue {
            softBounceSlider.doubleValue = sender.doubleValue
        }
        saveThresholds()
    }

    @objc private func softBounceChanged(_ sender: NSSlider) {
        if hardBounceSlider.doubleValue > sender.doubleValue {
            hardBounceSlider.doubleValue = sender.doubleValue
        }
        saveThresholds()
    }

    private func saveThresholds() {
        let hardBounceSeconds = hardBounceSlider.doubleValue.rounded() / 1000.0
        let softBounceSeconds = softBounceSlider.doubleValue.rounded() / 1000.0

        let defaults = UserDefaults.standard
        defaults.set(hardBounceSeconds, forKey: "hardBounceThreshold")
        defaults.set(softBounceSeconds, forKey: "softBounceThreshold")

        keyboardEngine?.hardBounceThreshold = hardBounceSeconds
        keyboardEngine?.softBounceThreshold = softBounceSeconds
        updateSliderLabels()
    }

    @objc private func flashCheckboxChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "enableFlash")
        appDelegate?.flashEnabled = enabled
    }

    @objc private func resetStats(_ sender: NSButton) {
        appDelegate?.resetBlockedCount()
    }

    @objc private func restoreDefaults(_ sender: NSButton) {
        hardBounceSlider.doubleValue = 40
        softBounceSlider.doubleValue = 100
        saveThresholds()

        enableFlashCheckbox.state = .on
        flashCheckboxChanged(enableFlashCheckbox)
    }

    func updateStatsLabel() {
        let count = appDelegate?.eventsBlocked ?? 0
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        eventsBlockedLabel?.stringValue = "Keystrokes blocked: \(formatted)"
    }
}
