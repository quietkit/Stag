import XCTest
import Cocoa
@testable import Stag

/// Pure key-capture rules extracted from EditorKeyCapture / ShortcutCapture.
final class KeyCaptureRulesTests: XCTestCase {

    // MARK: EditorToolKey

    func testPlainLetterPassesThrough() {
        XCTAssertEqual(EditorToolKey.binding(char: "a", modifiers: []), "a")
    }

    func testUppercaseIsLowercased() {
        XCTAssertEqual(EditorToolKey.binding(char: "A", modifiers: []), "a")
    }

    func testShiftPrefixesArrow() {
        XCTAssertEqual(EditorToolKey.binding(char: "a", modifiers: .shift), "\u{21E7}a")
    }

    func testNonShiftModifierDoesNotPrefix() {
        // Only an exact Shift gets the ⇧ prefix; Command alone does not.
        XCTAssertEqual(EditorToolKey.binding(char: "a", modifiers: .command), "a")
    }

    func testShiftPlusOtherModifierIsNotTreatedAsShift() {
        XCTAssertEqual(EditorToolKey.binding(char: "a", modifiers: [.shift, .command]), "a")
    }

    func testValidSymbolAccepted() {
        XCTAssertEqual(EditorToolKey.binding(char: "/", modifiers: []), "/")
        XCTAssertEqual(EditorToolKey.binding(char: "5", modifiers: []), "5")
    }

    func testEmptyAndInvalidRejected() {
        XCTAssertNil(EditorToolKey.binding(char: "", modifiers: []))
        XCTAssertNil(EditorToolKey.binding(char: " ", modifiers: []))
    }

    // MARK: HotKeyCaptureRule

    func testCombinationRequiresModifier() {
        XCTAssertNil(HotKeyCaptureRule.combination(keyCode: 18, modifiers: []))
    }

    func testCombinationKeepsKeyCodeAndModifiers() {
        let combo = HotKeyCaptureRule.combination(keyCode: 18, modifiers: [.command, .shift])
        XCTAssertEqual(combo?.keyCode, 18)
        let expected = NSEvent.ModifierFlags([.command, .shift]).rawValue
        XCTAssertEqual(combo?.modifiers, expected)
    }

    func testCombinationStripsNonDeviceIndependentBits() {
        // .capsLock is device-independent and should survive; throw in a high bit
        // that isn't part of deviceIndependentFlagsMask to confirm it's stripped.
        let stray = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | (1 << 1))
        let combo = HotKeyCaptureRule.combination(keyCode: 1, modifiers: stray)
        XCTAssertEqual(combo?.modifiers, NSEvent.ModifierFlags.command.rawValue)
    }
}
