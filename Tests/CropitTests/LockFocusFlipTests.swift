import XCTest
import AppKit

/// Determines the vertical orientation of an NSImage `lockFocus()` context, which
/// governs whether editor annotations (stored in y-down SwiftUI coords) need a
/// flip when re-drawn into the export context.
final class LockFocusFlipTests: XCTestCase {

    func testLockFocusIsYUp() throws {
        let img = NSImage(size: NSSize(width: 4, height: 4))
        img.lockFocus()
        NSColor.red.setFill()
        // Fill a 2×2 square at context origin (0,0).
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill()
        img.unlockFocus()

        let bm = try XCTUnwrap(img.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        // NSBitmapImageRep coordinates: (0,0) is the TOP-left of the pixel data.
        let topLeft = bm.colorAt(x: 0, y: 0)
        let bottomLeft = bm.colorAt(x: 0, y: bm.pixelsHigh - 1)

        let topIsRed = (topLeft?.redComponent ?? 0) > 0.5 && (topLeft?.greenComponent ?? 1) < 0.5
        let bottomIsRed = (bottomLeft?.redComponent ?? 0) > 0.5 && (bottomLeft?.greenComponent ?? 1) < 0.5

        // If the fill at (0,0) lands at the BOTTOM of the bitmap, the context is
        // y-up (origin bottom-left) → annotations stored in y-down need flipping.
        print("LOCKFOCUS_FLIP topIsRed=\(topIsRed) bottomIsRed=\(bottomIsRed)")
        XCTAssertNotEqual(topIsRed, bottomIsRed, "fill should be on exactly one side")
        // Record the result; we assert y-up because that's the AppKit default and
        // drives the export flip fix.
        XCTAssertTrue(bottomIsRed, "lockFocus context is expected to be y-up (origin bottom-left)")
    }
}
