import XCTest
import Cocoa
@testable import Stag

/// Format selection + encoding extracted from EditorView.writeImageSync and
/// unified with CaptureManager.saveJPEG.
final class ImageExportFormatTests: XCTestCase {

    // MARK: forPath

    func testPNGExtension() {
        XCTAssertEqual(ImageExportFormat.forPath("/tmp/shot.png"), .png)
    }

    func testJPGExtensionIsJPEGAt90() {
        XCTAssertEqual(ImageExportFormat.forPath("/tmp/shot.jpg"), .jpeg(quality: 0.9))
    }

    func testJPEGExtension() {
        XCTAssertEqual(ImageExportFormat.forPath("/tmp/shot.jpeg"), .jpeg(quality: 0.9))
    }

    func testExtensionMatchIsCaseInsensitive() {
        XCTAssertEqual(ImageExportFormat.forPath("/tmp/SHOT.JPG"), .jpeg(quality: 0.9))
        XCTAssertEqual(ImageExportFormat.forPath("/tmp/SHOT.PNG"), .png)
    }

    func testUnknownOrMissingExtensionDefaultsToPNG() {
        XCTAssertEqual(ImageExportFormat.forPath("/tmp/shot"), .png)
        XCTAssertEqual(ImageExportFormat.forPath("/tmp/shot.gif"), .png)
        XCTAssertEqual(ImageExportFormat.forPath("/tmp/shot.tiff"), .png)
    }

    // MARK: encoded(as:)

    private func solidImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        return image
    }

    func testEncodePNGHasPNGSignature() {
        let data = solidImage().encoded(as: .png)
        XCTAssertNotNil(data)
        XCTAssertEqual(Array(data!.prefix(4)), [0x89, 0x50, 0x4E, 0x47])  // \x89PNG
    }

    func testEncodeJPEGHasJPEGSignature() {
        let data = solidImage().encoded(as: .jpeg(quality: 0.8))
        XCTAssertNotNil(data)
        XCTAssertEqual(Array(data!.prefix(3)), [0xFF, 0xD8, 0xFF])  // SOI marker
    }
}
