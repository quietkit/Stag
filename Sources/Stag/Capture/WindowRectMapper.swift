import AppKit

/// Pure coordinate math shared by the window-picker overlays
/// (`WindowCaptureSource` and `ScrollingCaptureSource`), which previously each
/// carried a byte-for-byte identical copy. Extracted so it can be unit-tested
/// headlessly, with no window or display required.
enum WindowRectMapper {

    /// Maps a screen-space rect into an overlay view's coordinate space.
    /// - Parameters:
    ///   - screenRect: the rect in screen coordinates.
    ///   - windowFrame: the hosting window's frame in screen coordinates.
    ///   - isFlipped: whether the destination view uses a flipped (y-down) system.
    static func screenRectToView(_ screenRect: NSRect, windowFrame: NSRect, isFlipped: Bool) -> NSRect {
        if isFlipped {
            return NSRect(
                x: screenRect.minX - windowFrame.minX,
                y: windowFrame.height - screenRect.maxY + windowFrame.minY,
                width: screenRect.width,
                height: screenRect.height
            )
        }
        return NSRect(
            x: screenRect.minX - windowFrame.minX,
            y: screenRect.minY - windowFrame.minY,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    /// The four corners of a rect — bottom-left, bottom-right, top-right, top-left.
    static func cornerPoints(of rect: NSRect) -> [NSPoint] {
        [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.maxY),
        ]
    }
}
