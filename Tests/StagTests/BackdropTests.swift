import XCTest
import SwiftUI
import AppKit
@testable import Stag

/// "Beautiful screenshot" backdrop styling: proportional metrics, the hex color
/// decoder, and the Core Graphics export compositor.
final class BackdropTests: XCTestCase {

    // MARK: - hex decoder

    func testHexDecodesChannels() throws {
        let c = BackdropStyle.hex(0xFF8040)
        let ns = try XCTUnwrap(NSColor(c).usingColorSpace(.sRGB))
        XCTAssertEqual(Double(ns.redComponent),   1.0,           accuracy: 0.02)
        XCTAssertEqual(Double(ns.greenComponent), 128.0 / 255.0, accuracy: 0.02)
        XCTAssertEqual(Double(ns.blueComponent),  64.0 / 255.0,  accuracy: 0.02)
    }

    func testHexBlackAndWhite() throws {
        let white = try XCTUnwrap(NSColor(BackdropStyle.hex(0xFFFFFF)).usingColorSpace(.sRGB))
        let black = try XCTUnwrap(NSColor(BackdropStyle.hex(0x000000)).usingColorSpace(.sRGB))
        XCTAssertEqual(Double(white.redComponent), 1.0, accuracy: 0.01)
        XCTAssertEqual(Double(black.redComponent), 0.0, accuracy: 0.01)
    }

    // MARK: - presets

    func testGradientPresetsExistAndHaveTwoColors() {
        XCTAssertEqual(BackdropStyle.gradients.count, 8)
        for preset in BackdropStyle.gradients {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertEqual(preset.colors.count, 2)
        }
    }

    func testGradientPresetIDsAreUnique() {
        let ids = BackdropStyle.gradients.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - BackdropStyle.isActive

    func testIsActiveTracksKind() {
        var style = BackdropStyle()
        XCTAssertFalse(style.isActive)          // defaults to .none
        style.kind = .solid
        XCTAssertTrue(style.isActive)
    }

    // MARK: - BackdropMetrics

    func testBarHeightIsProportionalAndClamped() {
        XCTAssertEqual(BackdropMetrics.barHeight(width: 1000), 45, accuracy: 0.001) // 4.5%
        XCTAssertEqual(BackdropMetrics.barHeight(width: 100), 26, accuracy: 0.001)  // clamped to floor
        XCTAssertEqual(BackdropMetrics.barHeight(width: 5000), 56, accuracy: 0.001) // clamped to ceiling
    }

    func testCardSizeAddsBarOnlyWhenWindowFrameShown() {
        let content = CGSize(width: 800, height: 600)
        var style = BackdropStyle()
        style.showWindowFrame = false
        XCTAssertEqual(BackdropMetrics.cardSize(content: content, style: style), content)

        style.showWindowFrame = true
        let withBar = BackdropMetrics.cardSize(content: content, style: style)
        XCTAssertEqual(withBar.width, 800)
        XCTAssertEqual(withBar.height, 600 + BackdropMetrics.barHeight(width: 800), accuracy: 0.001)
    }

    func testPaddingUsesLongestEdge() {
        var style = BackdropStyle()
        style.paddingFraction = 0.1
        XCTAssertEqual(BackdropMetrics.padding(content: CGSize(width: 200, height: 400), style: style),
                       40, accuracy: 0.001)
    }

    // MARK: - compose

    func testComposeReturnsSameImageWhenInactive() {
        let content = NSImage(size: NSSize(width: 50, height: 50))
        var style = BackdropStyle()
        style.kind = .none
        let out = Backdrop.compose(content: content, style: style)
        XCTAssertEqual(out.size, content.size)
    }

    func testComposeEnlargesImageWhenActive() {
        let content = NSImage(size: NSSize(width: 100, height: 100))
        var style = BackdropStyle()
        style.kind = .solid
        style.paddingFraction = 0.08
        style.showWindowFrame = false
        let out = Backdrop.compose(content: content, style: style)
        // out = content + 2*pad on each axis, pad = 0.08 * 100 = 8 → 116×116
        XCTAssertEqual(out.size.width, 116, accuracy: 0.5)
        XCTAssertEqual(out.size.height, 116, accuracy: 0.5)
    }

    func testComposeWithWindowFrameAddsBarHeight() {
        let content = NSImage(size: NSSize(width: 200, height: 200))
        var style = BackdropStyle()
        style.kind = .gradient
        style.paddingFraction = 0.05
        style.showWindowFrame = true
        let out = Backdrop.compose(content: content, style: style)
        let bar = BackdropMetrics.barHeight(width: 200)
        let pad = 0.05 * 200.0
        XCTAssertEqual(out.size.width, (200 + 2 * pad).rounded(), accuracy: 0.5)
        XCTAssertEqual(out.size.height, (200 + bar + 2 * pad).rounded(), accuracy: 0.5)
    }

    func testComposeGuardsZeroSizedContent() {
        let content = NSImage(size: .zero)
        var style = BackdropStyle()
        style.kind = .solid
        let out = Backdrop.compose(content: content, style: style)
        XCTAssertEqual(out.size, .zero) // returns the content untouched
    }
}
