import XCTest
import SwiftUI
@testable import Stag

/// `#RRGGBB` formatting extracted from the editor's eyedropper / color readout.
final class HexColorTests: XCTestCase {

    func testChannelFormattingIsZeroPaddedUppercase() {
        XCTAssertEqual(HexColor.string(r: 255, g: 0, b: 16), "#FF0010")
        XCTAssertEqual(HexColor.string(r: 0, g: 0, b: 0), "#000000")
        XCTAssertEqual(HexColor.string(r: 255, g: 255, b: 255), "#FFFFFF")
    }

    func testFromColorPureChannels() {
        XCTAssertEqual(HexColor.string(from: Color(red: 1, green: 0, blue: 0)), "#FF0000")
        XCTAssertEqual(HexColor.string(from: Color(red: 0, green: 1, blue: 0)), "#00FF00")
        XCTAssertEqual(HexColor.string(from: Color(red: 0, green: 0, blue: 1)), "#0000FF")
        XCTAssertEqual(HexColor.string(from: Color(red: 0, green: 0, blue: 0)), "#000000")
    }

    func testStringAlwaysSevenCharacters() {
        XCTAssertEqual(HexColor.string(from: Color(red: 0.3, green: 0.6, blue: 0.9)).count, 7)
        XCTAssertTrue(HexColor.string(r: 1, g: 2, b: 3).hasPrefix("#"))
    }
}
