import AppKit
import CoreGraphics
import TextSnipperCore
import os

private enum CaptureKind {
    case text
    case image
}

@MainActor
final class CaptureSession {
    static let shared = CaptureSession()

    private var windows: [SelectionWindow] = []
    private var eventMonitors: [Any] = []
    private var previousApp: NSRunningApplication?
    private var selecting = false
    private var kind: CaptureKind = .text
    private var generation = 0
    private let logger = Logger(subsystem: "local.aliyevom.TextSnipper", category: "capture")

    private init() {}

    func beginText() {
        begin(kind: .text)
    }

    func beginScreenshot() {
        begin(kind: .image)
    }

    private func begin(kind: CaptureKind) {
        guard ScreenRecordingPermission.ensureAccess() else { return }
        if selecting {
            teardownUI()
        }
        guard !NSScreen.screens.isEmpty else {
            report(CaptureError.noDisplay)
            return
        }

        generation += 1
        selecting = true
        self.kind = kind
        rememberFrontApp()
        showOverlays()
    }

    func cancel() {
        guard selecting else { return }
        teardownUI()
        restoreFrontApp()
    }

    private func showOverlays() {
        windows = NSScreen.screens.map { screen in
            let window = SelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.isMovable = false
            window.becomesKeyOnlyIfNeeded = true
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            // Readable by ScreenCaptureKit so the capture filter can drop these windows
            // and photograph the desktop under the selection.
            window.sharingType = .readOnly
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.disableCursorRects()

            let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.isOpaque = false
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.onComplete = { [weak self, weak view, weak window] rect in
                guard let self, let view, let window else { return }
                self.finishSelection(rect, in: view, window: window)
            }
            view.onCancel = { [weak self] in
                self?.cancel()
            }
            window.contentView = view
            return window
        }

        for window in windows {
            window.orderFrontRegardless()
        }

        installCancelMonitors()
    }

    private func installCancelMonitors() {
        let cancelOnEscape: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                self?.cancel()
            }
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == 53 else { return event }
            cancelOnEscape(event)
            return nil
        }) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: cancelOnEscape) {
            eventMonitors.append(monitor)
        }
    }

    private func finishSelection(_ rect: CGRect, in view: NSView, window: NSWindow) {
        let screenRect = window.convertToScreen(view.convert(rect, to: nil))
        let token = generation
        let kind = self.kind
        if kind == .image {
            finishImage(screenRect: screenRect, token: token, windowIDs: windows.compactMap { overlay in
                guard overlay.windowNumber > 0 else { return nil }
                return CGWindowID(overlay.windowNumber)
            })
            return
        }
        let keepLineBreaks = SettingsStore.keepLineBreaks
        let codeCapture = SettingsStore.codeCapture
        let autoHeal = SettingsStore.autoHeal
        let windowIDs = windows.compactMap { overlay -> CGWindowID? in
            guard overlay.windowNumber > 0 else { return nil }
            return CGWindowID(overlay.windowNumber)
        }

        Task { @MainActor in
            do {
                let image = try await self.captureWithoutOverlay(screenRect: screenRect, windowIDs: windowIDs)
                guard token == self.generation else { return }
                self.teardownUI()
                let modelTask = Task<String?, Never> { @MainActor in
                    guard autoHeal else { return nil }
                    return await CaptureHeal.transcribe(image: image)
                }
                let recognition: CodeRecognition
                do {
                    recognition = try await Task.detached(priority: .userInitiated) {
                        try OCRService.inspect(image, keepLineBreaks: keepLineBreaks, codeCapture: codeCapture)
                    }.value
                } catch {
                    modelTask.cancel()
                    throw error
                }
                let text = recognition.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard token == self.generation else {
                    modelTask.cancel()
                    return
                }
                let model = await modelTask.value
                guard token == self.generation else { return }
                let healed = self.healedText(
                    text,
                    model: model,
                    codeCapture: codeCapture,
                    autoHeal: autoHeal
                )
                self.deliver(healed, near: screenRect)
            } catch {
                self.teardownUI()
                self.logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
                guard token == self.generation else { return }
                self.report(error)
            }
        }
    }

    private func finishImage(screenRect: CGRect, token: Int, windowIDs: [CGWindowID]) {
        Task { @MainActor in
            do {
                let image = try await self.captureWithoutOverlay(screenRect: screenRect, windowIDs: windowIDs)
                guard token == self.generation else { return }
                self.teardownUI()
                _ = try ShotPool.add(image)
                self.restoreFrontApp()
                NotificationCenter.default.post(name: .textSnipperShotPoolChanged, object: nil)
            } catch {
                self.teardownUI()
                self.logger.error("Screenshot failed: \(error.localizedDescription, privacy: .public)")
                guard token == self.generation else { return }
                self.report(error, title: "Could not save screenshot")
            }
        }
    }

    /// Photographs `screenRect` without the selection box.
    ///
    /// The first attempt leaves the box on screen and tells ScreenCaptureKit to skip
    /// those windows. If they cannot be skipped, the box is hidden and the shot is
    /// taken again so the border is not left in the image.
    private func captureWithoutOverlay(screenRect: CGRect, windowIDs: [CGWindowID]) async throws -> CGImage {
        let frame = try await ScreenGrabber.capture(screenRect: screenRect, excludingWindowIDs: windowIDs)
        if frame.didExcludeOverlay {
            return frame.image
        }

        logger.error("Selection windows were still shareable; hiding them before a second capture")
        for window in windows {
            window.alphaValue = 0
            window.orderOut(nil)
        }
        CATransaction.flush()
        try await Task.sleep(nanoseconds: 120_000_000)
        return try await ScreenGrabber.capture(screenRect: screenRect).image
    }

    private func healedText(
        _ text: String,
        model: String?,
        codeCapture: Bool,
        autoHeal: Bool
    ) -> String {
        var repaired = text
        if autoHeal, HealGate.shouldConsult(text, codeCapture: codeCapture), let model {
            repaired = CaptureHeal.accept(model, draft: text) ?? text
        }
        return URLLayout.joinWrappedLines(repaired)
    }

    private func deliver(_ text: String, near screenRect: CGRect) {
        if text.isEmpty {
            HUD.shared.show("No text found", near: screenRect)
        } else {
            Clipboard.copy(text)
        }
        restoreFrontApp()
    }

    private func teardownUI() {
        selecting = false
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    private func rememberFrontApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = front
        }
    }

    private func restoreFrontApp() {
        guard let previous = previousApp else { return }
        previousApp = nil
        if previous.processIdentifier != NSRunningApplication.current.processIdentifier {
            previous.activate(from: .current, options: [])
        }
    }

    private func report(_ error: Error, title: String = "Could not capture text") {
        restoreFrontApp()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Screen Recording Settings")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn {
            ScreenRecordingPermission.openSettings()
        }
    }
}

private enum Clipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

enum ScreenRecordingPermission {
    private static let promptedKey = "didPromptForScreenRecording"

    static func ensureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        let promptedBefore = UserDefaults.standard.bool(forKey: promptedKey)
        UserDefaults.standard.set(true, forKey: promptedKey)
        if CGRequestScreenCaptureAccess() {
            return true
        }
        if promptedBefore {
            let alert = NSAlert()
            alert.messageText = "Allow screen recording"
            alert.informativeText = "TextSnipper needs Screen Recording permission to read the area you select. Turn it on for TextSnipper, then press the shortcut again."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                openSettings()
            }
        }
        return false
    }

    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

private final class SelectionWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayView: NSView {
    var onComplete: (CGRect) -> Void = { _ in }
    var onCancel: () -> Void = {}

    private var anchor: CGPoint?
    private var selection: CGRect = .zero

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {}

    override func resetCursorRects() {}

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        updateSelection(with: event)
        if selection.width >= 8, selection.height >= 8 {
            onComplete(selection)
        } else {
            onCancel()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        }
    }

    private func updateSelection(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        var rect = CGRect(
            x: min(anchor.x, point.x),
            y: min(anchor.y, point.y),
            width: abs(anchor.x - point.x),
            height: abs(anchor.y - point.y)
        )
        rect = rect.intersection(bounds)
        selection = rect.isNull ? .zero : rect
    }
}
