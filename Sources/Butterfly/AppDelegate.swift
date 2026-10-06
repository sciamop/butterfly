import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var keyboardEngine: KeyboardEngine?
    private var flashTimer: Timer?
    private var permissionTimer: Timer?
    private var settingsWindow: SettingsWindowController?

    private var toggleItem: NSMenuItem!
    private var statsItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem?

    var flashEnabled: Bool = true
    private(set) var eventsBlocked: Int = 0

    private var isFilteringEnabled: Bool {
        keyboardEngine?.isEnabled ?? false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Create menu
        let menu = NSMenu()
        menu.delegate = self

        toggleItem = NSMenuItem(title: "Enable Filtering", action: #selector(toggleFiltering), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        statsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())

        if #available(macOS 13.0, *) {
            let item = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            launchAtLoginItem = item
        }

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Butterfly", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // Load persisted settings
        let defaults = UserDefaults.standard
        flashEnabled = defaults.object(forKey: "enableFlash") as? Bool ?? true
        eventsBlocked = defaults.integer(forKey: "eventsBlocked")

        // Initialize keyboard engine
        keyboardEngine = KeyboardEngine()
        keyboardEngine?.onEventBlocked = { [weak self] in
            self?.handleEventBlocked()
        }

        // Try to start filtering by default
        if keyboardEngine?.start() != true {
            showPermissionAlert()
            waitForPermission()
        }

        updateStatusUI()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Butterfly needs Accessibility permission to filter repeated keystrokes.\n\nEnable Butterfly in System Settings > Privacy & Security > Accessibility. Filtering will start automatically once permission is granted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Polls until the user grants Accessibility permission, then starts filtering — no restart needed.
    private func waitForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if KeyboardEngine.hasAccessibilityPermission(prompt: false),
               self.keyboardEngine?.start(promptForPermission: false) == true {
                timer.invalidate()
                self.permissionTimer = nil
                self.updateStatusUI()
            }
        }
    }

    @objc func toggleFiltering() {
        guard let engine = keyboardEngine else { return }

        if engine.isEnabled {
            engine.stop()
        } else if !engine.start() {
            showPermissionAlert()
            waitForPermission()
        }

        updateStatusUI()
    }

    @available(macOS 13.0, *)
    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't Change Login Item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(keyboardEngine: keyboardEngine, appDelegate: self)
        }
        settingsWindow?.showWindow(nil)
    }

    @objc func quit() {
        keyboardEngine?.stop()
        NSApplication.shared.terminate(nil)
    }

    func resetBlockedCount() {
        eventsBlocked = 0
        UserDefaults.standard.set(0, forKey: "eventsBlocked")
        settingsWindow?.updateStatsLabel()
    }

    // The event tap runs on the main run loop, so this is already on the main thread
    private func handleEventBlocked() {
        eventsBlocked += 1
        UserDefaults.standard.set(eventsBlocked, forKey: "eventsBlocked")
        settingsWindow?.updateStatsLabel()
        if flashEnabled {
            flashIcon()
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatusUI()
        if #available(macOS 13.0, *) {
            launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    // MARK: - Status item

    private func updateStatusUI() {
        if isFilteringEnabled {
            toggleItem.title = "Disable Filtering"
        } else if permissionTimer != nil {
            toggleItem.title = "Enable Filtering (Needs Permission)"
        } else {
            toggleItem.title = "Enable Filtering"
        }

        let noun = eventsBlocked == 1 ? "keystroke" : "keystrokes"
        statsItem.title = "\(NumberFormatter.localizedString(from: NSNumber(value: eventsBlocked), number: .decimal)) repeated \(noun) blocked"

        if let button = statusItem?.button, flashTimer == nil {
            button.image = statusImage()
        }
    }

    private func statusImage() -> NSImage? {
        let image = isFilteringEnabled
            ? NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: "Butterfly (Filtering On)")
            : NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Butterfly (Filtering Off)")
        image?.isTemplate = true
        return image
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardEngine?.stop()
    }

    private func flashIcon() {
        guard let button = statusItem?.button, let base = statusImage() else { return }

        flashTimer?.invalidate()

        // Tint the current icon orange
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.systemOrange.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        button.image = tinted

        // Restore after a brief flash, using whatever the current state is (it may have changed)
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.flashTimer = nil
            self.statusItem?.button?.image = self.statusImage()
        }
    }
}
