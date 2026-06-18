import XCTest
import CoreGraphics
@testable import Stag

/// Aspect-fit sizing extracted from CaptureManager.saveJPEGThumbnail.
final class ThumbnailGeometryTests: XCTestCase {

    func testLandscapeFitsToWidth() {
        let s = ThumbnailGeometry.fittedSize(for: CGSize(width: 640, height: 320), maxDimension: 320)
        XCTAssertEqual(s.width, 320, accuracy: 0.001)
        XCTAssertEqual(s.height, 160, accuracy: 0.001)
    }

    func testPortraitFitsToHeight() {
        let s = ThumbnailGeometry.fittedSize(for: CGSize(width: 320, height: 640), maxDimension: 320)
        XCTAssertEqual(s.width, 160, accuracy: 0.001)
        XCTAssertEqual(s.height, 320, accuracy: 0.001)
    }

    func testNeverUpscalesSmallImage() {
        let input = CGSize(width: 100, height: 80)
        let s = ThumbnailGeometry.fittedSize(for: input, maxDimension: 320)
        XCTAssertEqual(s, input)
    }

    func testAspectRatioPreserved() {
        let s = ThumbnailGeometry.fittedSize(for: CGSize(width: 1000, height: 250), maxDimension: 320)
        XCTAssertEqual(s.width / s.height, 4.0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(s.width, 320)
        XCTAssertLessThanOrEqual(s.height, 320)
    }

    func testZeroAndNegativeReturnZero() {
        XCTAssertEqual(ThumbnailGeometry.fittedSize(for: .zero, maxDimension: 320), .zero)
        XCTAssertEqual(ThumbnailGeometry.fittedSize(for: CGSize(width: -10, height: 50), maxDimension: 320), .zero)
    }

    func testSquareScalesUniformly() {
        let s = ThumbnailGeometry.fittedSize(for: CGSize(width: 800, height: 800), maxDimension: 320)
        XCTAssertEqual(s.width, 320, accuracy: 0.001)
        XCTAssertEqual(s.height, 320, accuracy: 0.001)
    }
}
