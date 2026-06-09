import Cocoa
import ScreenCaptureKit

/// A visible on-screen window, with its frame in CoreGraphics global coordinates
/// (origin = top-left of the primary display, y increasing downward — exactly
/// what `SCWindow.frame` returns).
struct DetectedWindow {
    let frame: CGRect
    let title: String
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
