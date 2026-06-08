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
    var shotTimestamp: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        return formatter.string(from: self)
            .replacingOccurrences(of: ":", with: "-")
    }
}
