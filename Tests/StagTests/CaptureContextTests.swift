import XCTest
@testable import Stag

/// Filename slug sanitization for naming captures after their source app.
final class CaptureContextTests: XCTestCase {

    override func tearDown() {
        CaptureContext.shared.sourceAppName = nil
        super.tearDown()
    }

    func testEmptySlugWhenNoSourceApp() {
        CaptureContext.shared.sourceAppName = nil
        XCTAssertEqual(CaptureContext.shared.filenameSlug(), "")
    }

    func testKeepsAlphanumericsSpacesHyphensUnderscores() {
        CaptureContext.shared.sourceAppName = "Google Chrome"
        XCTAssertEqual(CaptureContext.shared.filenameSlug(), "Google Chrome")

        CaptureContext.shared.sourceAppName = "My_App-2"
        XCTAssertEqual(CaptureContext.shared.filenameSlug(), "My_App-2")
    }

    func testStripsPathAndSpecialCharacters() {
        CaptureContext.shared.sourceAppName = "Finder/../:*?<>|"
        // only alphanumerics/space/-/_ survive
        XCTAssertEqual(CaptureContext.shared.filenameSlug(), "Finder")
    }

    func testTrimsSurroundingWhitespace() {
        CaptureContext.shared.sourceAppName = "  Safari  "
        XCTAssertEqual(CaptureContext.shared.filenameSlug(), "Safari")
    }

    func testCapsAtFortyCharacters() {
        CaptureContext.shared.sourceAppName = String(repeating: "a", count: 100)
        XCTAssertEqual(CaptureContext.shared.filenameSlug().count, 40)
    }
}
