import XCTest
import CoreGraphics
@testable import Cropit

/// Headless verification of the window CG-global → overlay-view coordinate
/// mapping used by the "click to capture a window" flow. These exercise the
/// multi-display layouts that are impractical to test by running the app.
final class WindowFrameMapperTests: XCTestCase {

    private func assertRect(_ a: CGRect, _ b: CGRect, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: 0.01, msg, file: file, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: 0.01, msg, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 0.01, msg, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: 0.01, msg, file: file, line: line)
    }

    // Single 1920×1080 display. A window 100pt from the left, 50pt from the top.
    func testSingleDisplay() {
        let total = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let win = CGRect(x: 100, y: 50, width: 400, height: 300)
        let out = WindowFrameMapper.viewRect(cgFrame: win, totalFrame: total, primaryHeight: 1080)
        assertRect(out, CGRect(x: 100, y: 50, width: 400, height: 300))
    }

    // Secondary display to the LEFT of primary. CG x is negative on the secondary.
    // Window 100pt from the secondary's left edge, 50pt from its top.
    func testSecondaryDisplayToLeft() {
        let total = CGRect(x: -1920, y: 0, width: 3840, height: 1080) // union, Cocoa
        let win = CGRect(x: -1820, y: 50, width: 400, height: 300)    // CG global
        let out = WindowFrameMapper.viewRect(cgFrame: win, totalFrame: total, primaryHeight: 1080)
        // 100pt from the overlay's left (the secondary's left), 50pt from the top.
        assertRect(out, CGRect(x: 100, y: 50, width: 400, height: 300))
    }

    // Secondary display ABOVE primary. Exercises offsetY = totalFrame.maxY - primaryHeight.
    func testSecondaryDisplayAbove() {
        let total = CGRect(x: 0, y: 0, width: 1920, height: 2160) // primary stacked under secondary
        let win = CGRect(x: 100, y: -1030, width: 400, height: 300) // CG: secondary is at negative y
        let out = WindowFrameMapper.viewRect(cgFrame: win, totalFrame: total, primaryHeight: 1080)
        // 50pt from the very top of the overlay (the secondary's top edge).
        assertRect(out, CGRect(x: 100, y: 50, width: 400, height: 300))
    }

    // A window on the primary when a taller secondary sits above it.
    func testPrimaryWindowWithTallerSecondaryAbove() {
        let total = CGRect(x: 0, y: 0, width: 1920, height: 2160)
        let win = CGRect(x: 200, y: 100, width: 500, height: 400)  // CG y>0 → on primary
        let out = WindowFrameMapper.viewRect(cgFrame: win, totalFrame: total, primaryHeight: 1080)
        // primary's top is 1080pt down from the overlay top, plus 100pt into it.
        assertRect(out, CGRect(x: 200, y: 1180, width: 500, height: 400))
    }
}
