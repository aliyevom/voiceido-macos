import AppKit

@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideWork: DispatchWorkItem?

    private init() {}

    func show(_ message: String, near screenRect: CGRect) {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let label else { return }

        label.stringValue = message
        label.sizeToFit()

        let width = max(96, label.frame.width + 36)
        let height = label.frame.height + 20
        label.frame = NSRect(
            x: (width - label.frame.width) / 2,
            y: (height - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )

        let screen = NSScreen.screens.first { $0.frame.intersects(screenRect) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        var origin = CGPoint(x: screenRect.midX - width / 2, y: screenRect.minY - height - 16)
        if origin.y < visible.minY + 8 {
            origin.y = screenRect.maxY + 16
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - height - 8)

        panel.setFrame(
            NSRect(origin: origin, size: CGSize(width: width, height: height)),
            display: true
        )
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak panel] in
            panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false

        let background = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        background.autoresizingMask = [.width, .height]
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        background.addSubview(label)

        panel.contentView = background
        self.label = label
        return panel
    }
}
