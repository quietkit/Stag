import XCTest
@testable import Stag

/// Post-processing rules extracted from the OCR / QR closures in CaptureManager
/// and EditorView.
final class TextRecognitionTests: XCTestCase {

    // MARK: OCR

    func testOCRNoLinesIsNoText() {
        XCTAssertEqual(TextRecognition.ocrOutcome(from: []), .noText)
    }

    func testOCREmptyStringsAreNoText() {
        XCTAssertEqual(TextRecognition.ocrOutcome(from: [""]), .noText)
    }

    func testOCRSingleLine() {
        XCTAssertEqual(TextRecognition.ocrOutcome(from: ["hello"]), .copied(text: "hello", lineCount: 1))
    }

    func testOCRMultipleLinesJoinAndCount() {
        XCTAssertEqual(
            TextRecognition.ocrOutcome(from: ["one", "two", "three"]),
            .copied(text: "one\ntwo\nthree", lineCount: 3)
        )
    }

    // MARK: Barcode / QR

    func testBarcodeNoneWhenEmpty() {
        XCTAssertEqual(TextRecognition.barcodeOutcome(from: []), .none)
    }

    func testBarcodeURLPayloadSurfacesURL() {
        let outcome = TextRecognition.barcodeOutcome(from: ["https://example.com"])
        XCTAssertEqual(
            outcome,
            .found(text: "https://example.com", count: 1,
                   url: URL(string: "https://example.com"), firstPayload: "https://example.com")
        )
    }

    func testBarcodeNonURLPayloadHasNilURL() {
        let outcome = TextRecognition.barcodeOutcome(from: ["just some text"])
        XCTAssertEqual(
            outcome,
            .found(text: "just some text", count: 1, url: nil, firstPayload: "just some text")
        )
    }

    func testBarcodeMailtoSchemeIsOpenable() {
        let outcome = TextRecognition.barcodeOutcome(from: ["mailto:a@b.com"])
        guard case .found(_, _, let url, _) = outcome else { return XCTFail("expected .found") }
        XCTAssertEqual(url?.scheme, "mailto")
    }

    func testBarcodeMultiplePayloadsJoinTextAndKeepFirstForURL() {
        let outcome = TextRecognition.barcodeOutcome(from: ["https://x.com", "extra"])
        XCTAssertEqual(
            outcome,
            .found(text: "https://x.com\nextra", count: 2,
                   url: URL(string: "https://x.com"), firstPayload: "https://x.com")
        )
    }

    func testBarcodeNonURLFirstWithMultipleHasNilURL() {
        let outcome = TextRecognition.barcodeOutcome(from: ["plain", "https://x.com"])
        guard case .found(_, let count, let url, let first) = outcome else { return XCTFail("expected .found") }
        XCTAssertNil(url)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(first, "plain")
    }
}
