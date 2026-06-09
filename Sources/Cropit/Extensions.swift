import Cocoa
import UniformTypeIdentifiers

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    func pngWrite(to url: URL) {
        guard let data = pngData else { return }
        try? data.write(to: url)
    }
}

extension Date {
    /// Filename-safe timestamp with millisecond resolution, e.g. `2026-06-10T14-30-45-123`.
    /// Millisecond precision prevents two captures in the same second from producing
    /// identical filenames (which silently overwrote the earlier file on disk).
    var shotTimestamp: String {
        Self.shotFormatter.string(from: self)
    }

    private static let shotFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss-SSS"
        return f
    }()
}
