import XCTest
import AppKit
@testable import Stag

/// Pure coordinate math extracted from the two window-picker overlays. Verifies
/// the flipped/non-flipped screen→view mapping and the corner enumeration that
/// were previously duplicated (and untested) in both capture sources.
final class WindowRectMapperTests: XCTestCase {

    private func assertRect(_ a: NSRect, _ b: NSRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: 0.001, file: file, line: line)
    }

    func testFlippedMappingAtOrigin() {
        let out = WindowRectMapper.screenRectToView(
            NSRect(x: 100, y: 100, width: 200, height: 150),
            windowFrame: NSRect(x: 0, y: 0, width: 1000, height: 800),
            isFlipped: true)
        // y = 800 - (100 + 150) + 0 = 550
        assertRect(out, NSRect(x: 100, y: 550, width: 200, height: 150))
    }

    func testFlippedMappingWithWindowOffset() {
        let out = WindowRectMapper.screenRectToView(
            NSRect(x: 100, y: 100, width: 200, height: 150),
            windowFrame: NSRect(x: 50, y: 30, width: 1000, height: 800),
            isFlipped: true)
        // x = 100 - 50 = 50 ; y = 800 - 250 + 30 = 580
        assertRect(out, NSRect(x: 50, y: 580, width: 200, height: 150))
    }

    func testNonFlippedMappingIsPlainTranslation() {
        let out = WindowRectMapper.screenRectToView(
            NSRect(x: 100, y: 100, width: 200, height: 150),
            windowFrame: NSRect(x: 50, y: 30, width: 1000, height: 800),
            isFlipped: false)
        assertRect(out, NSRect(x: 50, y: 70, width: 200, height: 150))
    }

    func testCornerPointsOrder() {
        let corners = WindowRectMapper.cornerPoints(of: NSRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(corners, [
            NSPoint(x: 10, y: 20),  // bottom-left
            NSPoint(x: 40, y: 20),  // bottom-right
            NSPoint(x: 40, y: 60),  // top-right
            NSPoint(x: 10, y: 60),  // top-left
        ])
    }
}
