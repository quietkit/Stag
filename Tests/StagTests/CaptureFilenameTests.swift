import XCTest
@testable import Stag

/// Filename assembly shared by CaptureManager (real save) and PreferencesWindow
/// (settings preview), plus CaptureFormat's extension mapping.
final class CaptureFilenameTests: XCTestCase {

    func testEmptyPrefixFallsBackToStag() {
        XCTAssertEqual(
            CaptureFilename.make(prefix: "", slug: "", timestamp: "2026-01-01", ext: "png"),
            "Stag_2026-01-01.png"
        )
    }

    func testCustomPrefixIsUsedVerbatim() {
        XCTAssertEqual(
            CaptureFilename.make(prefix: "Shot-", slug: "", timestamp: "2026-01-01", ext: "png"),
            "Shot-2026-01-01.png"
        )
    }

    func testSlugInsertedWithSeparatingSpace() {
        XCTAssertEqual(
            CaptureFilename.make(prefix: "", slug: "Slack", timestamp: "T", ext: "png"),
            "Stag_Slack T.png"
        )
    }

    func testEmptySlugOmitsSpace() {
        let result = CaptureFilename.make(prefix: "Stag_", slug: "", timestamp: "T", ext: "jpg")
        XCTAssertEqual(result, "Stag_T.jpg")
        XCTAssertFalse(result.contains("  "))
    }

    func testExtensionIsApplied() {
        XCTAssertEqual(
            CaptureFilename.make(prefix: "P", slug: "App", timestamp: "ts", ext: "jpg"),
            "PApp ts.jpg"
        )
    }

    func testCaptureFormatFileExtension() {
        XCTAssertEqual(CaptureFormat.png.fileExtension, "png")
        XCTAssertEqual(CaptureFormat.jpeg.fileExtension, "jpg")
    }
}
