import AppKit
import CoreGraphics
import ScreenCaptureKit
import TextSnipperCore

enum CaptureError: LocalizedError {
    case noDisplay
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "TextSnipper could not find the display for that selection."
        case .emptySelection:
            return "Drag a larger area around the text."
        }
    }
}

struct CaptureFrame {
    /// Pixels under the selection, without the selection chrome.
    var image: CGImage
    /// True when this app's selection windows were removed from the shot.
    var didExcludeOverlay: Bool
}

@MainActor
enum ScreenGrabber {
    /// Captures `screenRect` and leaves TextSnipper's selection windows out of the image.
    ///
    /// The selection window stays on screen so the drag box is still visible, but the
    /// filter reads the desktop underneath it. The border is never part of the picture
    /// that OCR reads.
    static func capture(screenRect: CGRect, excludingWindowIDs: [CGWindowID] = []) async throws -> CaptureFrame {
        let rect = screenRect.standardized
        guard rect.width >= 2, rect.height >= 2 else {
            throw CaptureError.emptySelection
        }

        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY))
        }) ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) }) else {
            throw CaptureError.noDisplay
        }
        guard let displayID = screen.displayID else {
            throw CaptureError.noDisplay
        }
        guard let source = CaptureGeometry.displaySourceRect(globalRect: rect, screenFrame: screen.frame) else {
            throw CaptureError.emptySelection
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }

        let (filter, didExcludeOverlay) = contentFilter(
            for: display,
            in: content,
            excludingWindowIDs: excludingWindowIDs
        )
        let config = SCStreamConfiguration()
        config.sourceRect = source
        config.showsCursor = false
        let scale = max(screen.backingScaleFactor, 1)
        config.width = max(1, Int((source.width * scale).rounded()))
        config.height = max(1, Int((source.height * scale).rounded()))
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return CaptureFrame(image: image, didExcludeOverlay: didExcludeOverlay)
    }

    private static func contentFilter(
        for display: SCDisplay,
        in content: SCShareableContent,
        excludingWindowIDs: [CGWindowID]
    ) -> (SCContentFilter, Bool) {
        let ids = Set(excludingWindowIDs)
        let overlayWindows = content.windows.filter { ids.contains($0.windowID) }
        if !overlayWindows.isEmpty {
            return (SCContentFilter(display: display, excludingWindows: overlayWindows), true)
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier
        let ownApps = content.applications.filter { app in
            if app.processID == pid { return true }
            if let bundleID, !bundleID.isEmpty, app.bundleIdentifier == bundleID { return true }
            return false
        }
        if !ownApps.isEmpty, !ids.isEmpty {
            return (
                SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: []),
                true
            )
        }
        return (SCContentFilter(display: display, excludingWindows: []), false)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
