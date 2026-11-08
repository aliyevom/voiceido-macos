import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeys = HotkeyManager()
    private let textHotkey: UInt32 = 1
    private let screenshotHotkey: UInt32 = 2
    private let clearHotkey: UInt32 = 3
    private let shortcutPanel = ShortcutPanelController()
    private var captureItem: NSMenuItem!
    private var screenshotItem: NSMenuItem!
    private var clearShotsItem: NSMenuItem!
    private var lineBreakItem: NSMenuItem!
    private var codeCaptureItem: NSMenuItem!
    private var autoHealItem: NSMenuItem!
    private var balanceItem: NSMenuItem!
    private var balanceFetch: Task<Void, Never>?
    private var balanceTimer: Timer?
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if terminateIfAlreadyRunning() {
            return
        }
        ProcessInfo.processInfo.disableAutomaticTermination("TextSnipper stays in the menu bar")
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "TextSnipper stays ready to capture text"
        )
        setupMenuBar()
        ShotPool.restore()
        hotkeys.onPressed = { [weak self] id in
            guard let self else { return }
            switch id {
            case self.textHotkey:
                self.captureText()
            case self.screenshotHotkey:
                self.captureScreenshot()
            case self.clearHotkey:
                self.clearScreenshots()
            default:
                break
            }
        }
        if !hotkeys.register(SettingsStore.shortcut, id: textHotkey) {
            showAlert(
                title: "Shortcut not available",
                message: "\(KeyDisplay.shortcutString(SettingsStore.shortcut)) is already used. Choose another shortcut from the TextSnipper menu."
            )
        }
        if !hotkeys.register(Shortcut.screenshot, id: screenshotHotkey) {
            showAlert(
                title: "Screenshot shortcut not available",
                message: "Command-Shift-1 is already used. Capture Screenshot in the menu still works."
            )
        }
        hotkeys.register(Shortcut.clearShots, id: clearHotkey)
        updateMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshBalanceFromSpend),
            name: .textSnipperSpentFalCredit,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shotPoolChanged),
            name: .textSnipperShotPoolChanged,
            object: nil
        )
        refreshBalance()
        balanceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshBalance()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func appIcon(pointSize: CGFloat) -> NSImage? {
        let image = Bundle.main.url(forResource: "AppIcon", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        image?.isTemplate = false
        image?.size = NSSize(width: pointSize, height: pointSize)
        return image
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = appIcon(pointSize: 18)
        }

        let menu = NSMenu()
        captureItem = NSMenuItem(title: "Capture Text", action: #selector(captureText), keyEquivalent: "")
        captureItem.target = self
        lineBreakItem = NSMenuItem(title: "Keep Line Breaks", action: #selector(toggleLineBreaks), keyEquivalent: "")
        lineBreakItem.target = self
        codeCaptureItem = NSMenuItem(title: "Code Capture", action: #selector(toggleCodeCapture), keyEquivalent: "")
        codeCaptureItem.target = self
        autoHealItem = NSMenuItem(title: "Auto-heal", action: #selector(toggleAutoHeal), keyEquivalent: "")
        autoHealItem.target = self
        balanceItem = NSMenuItem(title: "fal.ai balance …", action: #selector(openBilling), keyEquivalent: "")
        balanceItem.target = self
        let shortcutItem = NSMenuItem(title: "Change Shortcut…", action: #selector(changeShortcut), keyEquivalent: "")
        shortcutItem.target = self
        let quitItem = NSMenuItem(title: "Quit TextSnipper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        screenshotItem = NSMenuItem(title: "Capture Screenshot", action: #selector(captureScreenshot), keyEquivalent: "1")
        screenshotItem.keyEquivalentModifierMask = [.command, .shift]
        screenshotItem.target = self
        clearShotsItem = NSMenuItem(title: "Clear Screenshots", action: #selector(clearScreenshots), keyEquivalent: "0")
        clearShotsItem.keyEquivalentModifierMask = [.command, .shift]
        clearShotsItem.target = self

        menu.addItem(captureItem)
        menu.addItem(screenshotItem)
        menu.addItem(clearShotsItem)
        menu.addItem(.separator())
        menu.addItem(lineBreakItem)
        menu.addItem(codeCaptureItem)
        menu.addItem(autoHealItem)
        menu.addItem(balanceItem)
        menu.addItem(shortcutItem)
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func updateMenu() {
        let shortcut = SettingsStore.shortcut
        captureItem.title = "Capture Text"
        if let equivalent = KeyDisplay.menuKeyEquivalent(for: shortcut.keyCode) {
            captureItem.keyEquivalent = equivalent
            captureItem.keyEquivalentModifierMask = shortcut.modifierFlags
        } else {
            captureItem.keyEquivalent = ""
            captureItem.title = "Capture Text (\(KeyDisplay.shortcutString(shortcut)))"
        }
        lineBreakItem.state = SettingsStore.keepLineBreaks ? .on : .off
        codeCaptureItem.state = SettingsStore.codeCapture ? .on : .off
        autoHealItem.state = SettingsStore.autoHeal ? .on : .off
        let saved = ShotPool.count
        screenshotItem.title = saved == 0 ? "Capture Screenshot" : "Capture Screenshot (\(saved) saved)"
        clearShotsItem.title = saved == 0 ? "Clear Screenshots" : "Clear \(saved) Screenshots"
        statusItem.length = NSStatusItem.squareLength
        statusItem.button?.title = ""
        statusItem.button?.toolTip = saved == 0
            ? "TextSnipper — \(KeyDisplay.shortcutString(shortcut))"
            : "TextSnipper — \(saved) screenshots, Command-V pastes them"
    }

    @objc private func captureText() {
        CaptureSession.shared.beginText()
    }

    @objc private func captureScreenshot() {
        CaptureSession.shared.beginScreenshot()
    }

    @objc private func clearScreenshots() {
        ShotPool.reset()
        updateMenu()
    }

    @objc private func shotPoolChanged() {
        updateMenu()
    }

    @objc private func toggleLineBreaks() {
        SettingsStore.keepLineBreaks.toggle()
        updateMenu()
    }

    @objc private func toggleCodeCapture() {
        SettingsStore.codeCapture.toggle()
        updateMenu()
    }

    @objc private func toggleAutoHeal() {
        SettingsStore.autoHeal.toggle()
        updateMenu()
    }

    @objc private func openBilling() {
        guard let url = URL(string: "https://fal.ai/dashboard/billing") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func refreshBalanceFromSpend() {
        refreshBalance()
    }

    private func refreshBalance() {
        guard balanceFetch == nil else { return }
        balanceFetch = Task { @MainActor in
            let snapshot = await FalBalance.fetch()
            balanceFetch = nil
            balanceItem.title = FalBalance.title(for: snapshot)
        }
    }

    @objc private func changeShortcut() {
        hotkeys.unregister(textHotkey)
        shortcutPanel.onSubmit = { [weak self] shortcut in
            self?.applyShortcut(shortcut)
        }
        shortcutPanel.onCancel = { [weak self] in
            self?.restoreShortcut()
        }
        shortcutPanel.show()
    }

    @objc private func quit() {
        hotkeys.unregisterAll()
        NSApp.terminate(nil)
    }

    private func applyShortcut(_ shortcut: Shortcut) {
        if hotkeys.register(shortcut, id: textHotkey) {
            SettingsStore.shortcut = shortcut
            updateMenu()
            return
        }
        restoreShortcut()
        showAlert(
            title: "Shortcut not available",
            message: "macOS or another app is already using that shortcut. Pick a different one."
        )
    }

    private func restoreShortcut() {
        if !hotkeys.register(SettingsStore.shortcut, id: textHotkey) {
            showAlert(
                title: "Shortcut not available",
                message: "The previous shortcut could not be restored. Choose a new one from the menu."
            )
        }
        updateMenu()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    private func terminateIfAlreadyRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }
        NSApp.terminate(nil)
        return true
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshBalance()
    }
}
