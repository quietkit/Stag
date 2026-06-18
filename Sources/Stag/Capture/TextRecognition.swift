import Foundation

/// What an OCR pass produced, once the per-observation strings have been pulled
/// out of Vision.
enum OCROutcome: Equatable {
    case noText
    case copied(text: String, lineCount: Int)
}

/// What a barcode/QR scan produced, once payload strings have been pulled out of
/// Vision. `text` is always the clipboard text (all payloads joined); `url` is
/// set only when the first payload parses as an openable URL.
enum BarcodeOutcome: Equatable {
    case none
    case found(text: String, count: Int, url: URL?, firstPayload: String)
}

/// Pure post-processing for Vision text/barcode results, lifted out of the OCR
/// closures in CaptureManager and EditorView so the classification rules are
/// testable without Vision.
enum TextRecognition {

    /// Joins recognized OCR lines and classifies the outcome. `lines` are the
    /// per-observation strings already pulled from Vision.
    static func ocrOutcome(from lines: [String]) -> OCROutcome {
        let joined = lines.joined(separator: "\n")
        guard !joined.isEmpty else { return .noText }
        return .copied(text: joined, lineCount: joined.components(separatedBy: "\n").count)
    }

    /// Classifies decoded barcode payloads. When the first payload parses as a
    /// URL with a scheme, the URL is surfaced so the caller can offer to open it;
    /// the clipboard text is always every payload joined by newlines.
    static func barcodeOutcome(from payloads: [String]) -> BarcodeOutcome {
        guard let first = payloads.first else { return .none }
        let combined = payloads.joined(separator: "\n")
        let url: URL? = {
            guard let candidate = URL(string: first), candidate.scheme != nil else { return nil }
            return candidate
        }()
        return .found(text: combined, count: payloads.count, url: url, firstPayload: first)
    }
}
