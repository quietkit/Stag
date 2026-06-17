import AppKit

/// Centralizes the handful of `NSPasteboard` idioms that were copy-pasted across
/// the capture pipeline, editor, and history browser. Keeping the
/// `clearContents()` + write pairing in one place removes ~14 duplicated blocks
/// and gives a single, testable seam for clipboard behavior.
///
/// The `pasteboard` parameter defaults to `.general` in production but lets tests
/// pass a private, uniquely-named pasteboard so they never clobber the real one.
enum Clipboard {

    /// Replaces the clipboard contents with an image. Returns whether the write succeeded.
    @discardableResult
    static func copy(image: NSImage, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    /// Replaces the clipboard contents with a plain-text string.
    static func copy(text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Reads a PNG image from the clipboard, if present.
    static func image(from pasteboard: NSPasteboard = .general) -> NSImage? {
        guard let data = pasteboard.data(forType: .png) else { return nil }
        return NSImage(data: data)
    }
}
