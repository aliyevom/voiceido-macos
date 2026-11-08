import CoreGraphics

public enum CaptureGeometry {
    /// Converts a rectangle in AppKit screen coordinates (origin at the bottom-left
    /// of the primary display, y upward) into a ScreenCaptureKit display source
    /// rect (origin at the top-left of that display, y downward).
    public static func displaySourceRect(globalRect: CGRect, screenFrame: CGRect) -> CGRect? {
        let global = globalRect.standardized
        let screen = screenFrame.standardized
        let clipped = global.intersection(screen)
        guard !clipped.isNull, !clipped.isInfinite, clipped.width >= 1, clipped.height >= 1 else {
            return nil
        }
        return CGRect(
            x: clipped.minX - screen.minX,
            y: screen.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        )
    }
}
