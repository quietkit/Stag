import XCTest
import AppKit
@testable import Stag

/// `NSImage` PNG helpers and the filename-safe timestamp formatter.
final class ExtensionsTests: XCTestCase {

    private func filledImage(_ size: NSSize = NSSize(width: 8, height: 8)) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        img.unlockFocus()
        return img
    }

    func testPNGDataIsDecodable() throws {
        let data = try XCTUnwrap(filledImage().pngData)
        XCTAssertFalse(data.isEmpty)
        // PNG magic number
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertNotNil(NSBitmapImageRep(data: data))
    }

    func testPNGWriteCreatesFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stag-ext-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        filledImage().pngWrite(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        XCTAssertGreaterThan(size ?? 0, 0)
    }

    func testShotTimestampMatchesFilenameSafePattern() {
        let stamp = Date().shotTimestamp
        // yyyy-MM-dd'T'HH-mm-ss-SSS, e.g. 2026-06-16T10-30-45-123 — no ':' or '/'.
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}$"#
        XCTAssertNotNil(stamp.range(of: pattern, options: .regularExpression),
                        "unexpected timestamp format: \(stamp)")
        XCTAssertFalse(stamp.contains(":"))
        XCTAssertFalse(stamp.contains("/"))
    }

    func testShotTimestampIsStableForSameInstant() {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        XCTAssertEqual(date.shotTimestamp, date.shotTimestamp)
    }
}
