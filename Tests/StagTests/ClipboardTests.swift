import XCTest
import AppKit
@testable import Stag

/// The `Clipboard` helper that replaced the duplicated `NSPasteboard` blocks.
/// Tests use a private, uniquely-named pasteboard so the developer's real
/// clipboard is never touched.
final class ClipboardTests: XCTestCase {

    private var pb: NSPasteboard!

    override func setUp() {
        super.setUp()
        pb = NSPasteboard(name: NSPasteboard.Name("com.ganwar.Stag.tests-\(UUID().uuidString)"))
        pb.clearContents()
    }

    override func tearDown() {
        pb.releaseGlobally()
        pb = nil
        super.tearDown()
    }

    private func filledImage(_ side: CGFloat = 8) -> NSImage {
        let img = NSImage(size: NSSize(width: side, height: side))
        img.lockFocus()
        NSColor.green.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
        img.unlockFocus()
        return img
    }

    func testCopyTextWritesString() {
        Clipboard.copy(text: "hello world", to: pb)
        XCTAssertEqual(pb.string(forType: .string), "hello world")
    }

    func testCopyTextClearsPreviousContents() {
        Clipboard.copy(text: "first", to: pb)
        Clipboard.copy(text: "second", to: pb)
        XCTAssertEqual(pb.string(forType: .string), "second")
    }

    func testCopyImageSucceedsAndIsReadable() {
        XCTAssertTrue(Clipboard.copy(image: filledImage(), to: pb))
        let objects = pb.readObjects(forClasses: [NSImage.self], options: nil)
        XCTAssertEqual(objects?.count, 1)
    }

    func testImageReadsPNGFromPasteboard() throws {
        let png = try XCTUnwrap(filledImage().pngData)
        pb.clearContents()
        pb.setData(png, forType: .png)
        XCTAssertNotNil(Clipboard.image(from: pb))
    }

    func testImageReturnsNilWhenNoPNGPresent() {
        pb.clearContents()
        pb.setString("not an image", forType: .string)
        XCTAssertNil(Clipboard.image(from: pb))
    }
}
