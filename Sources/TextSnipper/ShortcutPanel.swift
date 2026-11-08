import AppKit

@MainActor
final class ShortcutPanelController: NSObject, NSWindowDelegate {
    var onSubmit: (Shortcut) -> Void = { _ in }
    var onCancel: () -> Void = {}

    private var panel: NSPanel?
    private var hint: NSTextField?
    private var finished = false

    func show() {
        finished = false

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 148),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Change Shortcut"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()

        let view = ShortcutCaptureView(frame: NSRect(x: 0, y: 0, width: 400, height: 148))
        view.onKey = { [weak self] event in
            self?.handle(event)
        }

        let label = NSTextField(wrappingLabelWithString: "Press a shortcut that includes ⌘, ⌥, or ⌃. Escape cancels.")
        label.frame = NSRect(x: 20, y: 64, width: 360, height: 44)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        view.addSubview(label)
        hint = label

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: 280, y: 16, width: 96, height: 32)
        cancel.refusesFirstResponder = true
        view.addSubview(cancel)

        panel.contentView = view
        panel.initialFirstResponder = view
        self.panel = panel

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        onCancel()
    }

    @objc private func cancelClicked() {
        close(submit: nil)
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 {
            close(submit: nil)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let relevant = flags.intersection([.command, .option, .control, .shift])
        guard relevant.contains(.command) || relevant.contains(.option) || relevant.contains(.control) else {
            hint?.stringValue = "Include ⌘, ⌥, or ⌃, then the key."
            return
        }

        let shortcut = Shortcut(
            keyCode: event.keyCode,
            command: relevant.contains(.command),
            shift: relevant.contains(.shift),
            option: relevant.contains(.option),
            control: relevant.contains(.control)
        )
        close(submit: shortcut)
    }

    private func close(submit: Shortcut?) {
        guard !finished else { return }
        finished = true
        panel?.close()
        if let submit {
            onSubmit(submit)
        } else {
            onCancel()
        }
    }
}

private final class ShortcutCaptureView: NSView {
    var onKey: (NSEvent) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKey(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKey(event)
        return true
    }
}
