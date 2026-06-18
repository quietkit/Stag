import CoreGraphics

/// Pure sizing math for capture thumbnails, lifted out of CaptureManager so the
/// aspect-fit rule can be tested without any AppKit drawing.
enum ThumbnailGeometry {
    /// Scales `size` down to fit within a `maxDimension` box (applied to each
    /// side), preserving aspect ratio. Never upscales. Returns `.zero` for
    /// non-positive input so callers can skip drawing.
    static func fittedSize(for size: CGSize, maxDimension: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
