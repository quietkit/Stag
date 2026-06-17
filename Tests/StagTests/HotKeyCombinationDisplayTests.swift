import XCTest
import Cocoa
@testable import Stag

/// Display-string formatting extracted from PreferencesWindow's shortcut row.
final class HotKeyCombinationDisplayTests: XCTestCase {

    private func combo(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> HotKeyCombination {
        HotKeyCombination(keyCode: keyCode, modifiers: flags.rawValue)
    }

    func testCommandShiftDigit() {
        // keyCode 18 == "1"; modifiers render in ⌃⌥⇧⌘ order.
        XCTAssertEqual(combo(18, [.command, .shift]).displayString, "\u{21E7}\u{2318}1")
    }

    func testModifierOrderingIsControlOptionShiftCommand() {
        let s = combo(8, [.command, .control, .shift, .option]).displayString  // 8 == "C"
        XCTAssertEqual(s, "\u{2303}\u{2325}\u{21E7}\u{2318}C")
    }

    func testNonSequentialDigitKeycodes() {
        // Regression guard: kVK_ANSI_5 = 23, kVK_ANSI_6 = 22.
        XCTAssertEqual(HotKeyCombination.keyName(23), "5")
        XCTAssertEqual(HotKeyCombination.keyName(22), "6")
    }

    func testUnknownKeycodeFallsBack() {
        XCTAssertEqual(HotKeyCombination.keyName(99), "Key99")
        XCTAssertEqual(combo(99, [.command]).displayString, "\u{2318}Key99")
    }

    func testZeroKeyCodeIsEmpty() {
        XCTAssertEqual(combo(0, [.command]).displayString, "")
    }

    func testSpecialKeyLabels() {
        XCTAssertEqual(HotKeyCombination.keyName(49), "Space")
        XCTAssertEqual(HotKeyCombination.keyName(36), "Return")
        XCTAssertEqual(HotKeyCombination.keyName(53), "Esc")
    }
}
