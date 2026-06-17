import XCTest
@testable import Stag

/// CanvasHistoryTests already exercises the history rules via the
/// `CanvasHistory = BoundedHistory<CanvasState>` typealias. These tests pin the
/// generic behavior with a value type other than CanvasState (mirroring the
/// image-undo use, BoundedHistory<NSImage>) so the generalization can't regress.
final class BoundedHistoryTests: XCTestCase {

    func testGenericRecordUndoRedoRoundTrip() {
        var h = BoundedHistory<Int>()
        h.record(1)
        XCTAssertTrue(h.canUndo)
        XCTAssertEqual(h.undo(current: 2), 1)   // returns previous, 2 -> redo
        XCTAssertFalse(h.canUndo)
        XCTAssertTrue(h.canRedo)
        XCTAssertEqual(h.redo(current: 1), 2)   // returns swapped, 1 -> undo
        XCTAssertTrue(h.canUndo)
    }

    func testRecordingClearsRedo() {
        var h = BoundedHistory<Int>()
        h.record(1)
        _ = h.undo(current: 2)
        XCTAssertTrue(h.canRedo)
        h.record(3)
        XCTAssertFalse(h.canRedo)
    }

    func testEmptyReturnsNil() {
        var h = BoundedHistory<Int>()
        XCTAssertNil(h.undo(current: 0))
        XCTAssertNil(h.redo(current: 0))
    }

    func testCapDropsOldest() {
        var h = BoundedHistory<Int>(limit: 20)
        for i in 1...25 { h.record(i) }          // retains 6...25
        var popped: [Int] = []
        var current = 999
        while let v = h.undo(current: current) { popped.append(v); current = v }
        XCTAssertEqual(popped.count, 20)
        XCTAssertEqual(popped.first, 25)         // most recent first
        XCTAssertEqual(popped.last, 6)           // 1...5 were dropped
    }
}
