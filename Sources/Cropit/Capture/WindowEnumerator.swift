import Cocoa
import ScreenCaptureKit

/// A visible on-screen window, with its frame in CoreGraphics global coordinates
/// (origin = top-left of the primary display, y increasing downward — exactly
/// what `SCWindow.frame` returns).
struct DetectedWindow {
    let frame: CGRect
    let title: String
}

/// Pure coordinate math for mapping a window's CG-global frame into the overlay's
/// view space. Extracted so it can be unit-tested headlessly across multi-display
/// layouts (no window/display required).
enum WindowFrameMapper {
    /// - Parameters:
    ///   - cgFrame: window frame in CG global coords (origin = top-left of the
    ///     primary display, y increasing downward) — i.e. `SCWindow.frame`.
    ///   - totalFrame: union of all `NSScreen.frame`s (Cocoa, y-up, origin
    ///     bottom-left of the primary display).
    ///   - primaryHeight: height of the primary display (the one at Cocoa origin).
    /// - Returns: the rect in the overlay's SwiftUI view space (origin at the
    ///   overlay's top-left, y increasing downward).
    static func viewRect(cgFrame: CGRect, totalFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        let offsetY = totalFrame.maxY - primaryHeight
        return CGRect(x: cgFrame.minX - totalFrame.minX,
                      y: offsetY + cgFrame.minY,
                      width: cgFrame.width,
                      height: cgFrame.height)
    }
}

/// Lists normal, visible application windows for the "hover-to-highlight, click to
/// capture that window" area-capture flow (the CleanShot-style interaction).
enum WindowEnumerator {
    static func enumerate() async -> [DetectedWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true) else { return [] }
        return windows(from: content)
    }

    static func windows(from content: SCShareableContent) -> [DetectedWindow] {
        let ourBundleID = Bundle.main.bundleIdentifier ?? ""
        let minSide: CGFloat = 40

        // SCShareableContent.windows is front-to-back; preserve that order so the
        // first window containing the cursor is the topmost one.
        return content.windows.compactMap { w in
            guard w.isOnScreen,
                  w.windowLayer == 0,                       // normal app windows only
                  w.frame.width >= minSide, w.frame.height >= minSide,
                  w.owningApplication?.bundleIdentifier != ourBundleID
            else { return nil }
            let title = w.title?.isEmpty == false ? w.title! : (w.owningApplication?.applicationName ?? "")
            return DetectedWindow(frame: w.frame, title: title)
        }
    }
}
