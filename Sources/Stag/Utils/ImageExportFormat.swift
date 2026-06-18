import Cocoa

/// The on-disk encoding for an exported image. Centralizes the format choice and
/// the encode-to-`Data` step that were previously inlined (and, for JPEG,
/// duplicated) across the editor's save path and CaptureManager.
enum ImageExportFormat: Equatable {
    case png
    case jpeg(quality: Double)

    /// Chooses a format from a destination path's extension: `.jpg`/`.jpeg` →
    /// JPEG (quality 0.9), anything else → PNG.
    static func forPath(_ path: String) -> ImageExportFormat {
        let lower = path.lowercased()
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") {
            return .jpeg(quality: 0.9)
        }
        return .png
    }
}

extension NSImage {
    /// Encodes the image to `Data` in the given format, or `nil` if encoding fails.
    func encoded(as format: ImageExportFormat) -> Data? {
        switch format {
        case .png:
            return pngData
        case .jpeg(let quality):
            let props: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: quality]
            return tiffRepresentation
                .flatMap { NSBitmapImageRep(data: $0) }
                .flatMap { $0.representation(using: .jpeg, properties: props) }
        }
    }
}
