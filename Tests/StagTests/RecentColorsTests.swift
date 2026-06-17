import XCTest
import SwiftUI
@testable import Stag

/// MRU/dedup/cap logic for the editor's recent-color swatches.
final class RecentColorsTests: XCTestCase {

    private let a = Color(red: 1, green: 0, blue: 0)
    private let b = Color(red: 0, green: 1, blue: 0)
    private let c = Color(red: 0, green: 0, blue: 1)

    func testRecordingIntoEmpty() {
        XCTAssertEqual(RecentColors.recording(a, into: []), [a])
    }

    func testNewColorGoesToFront() {
        XCTAssertEqual(RecentColors.recording(c, into: [a, b]), [c, a, b])
    }

    func testExistingColorMovesToFrontWithoutDuplicating() {
        XCTAssertEqual(RecentColors.recording(b, into: [a, b, c]), [b, a, c])
    }

    func testCapsAtLimitDroppingOldest() {
        // Fill beyond the limit with distinct grays, newest recorded last.
        var history: [Color] = []
        for i in 0..<12 {
            history = RecentColors.recording(Color(white: Double(i) / 12.0), into: history)
        }
        XCTAssertEqual(history.count, RecentColors.limit)
        // The most recent (i = 11) is first; the oldest survivors dropped off the end.
        XCTAssertEqual(history.first, Color(white: 11.0 / 12.0))
    }

    func testRecordingExistingAtCapacityKeepsCount() {
        var history: [Color] = (0..<RecentColors.limit).map { Color(white: Double($0) / 10.0) }
        let existing = history[3]
        history = RecentColors.recording(existing, into: history)
        XCTAssertEqual(history.count, RecentColors.limit)
        XCTAssertEqual(history.first, existing)
    }

    func testCustomLimit() {
        let out = RecentColors.recording(c, into: [a, b], limit: 2)
        XCTAssertEqual(out, [c, a])
    }
}
