import XCTest
@testable import Stag

/// Bounded undo/redo history extracted from EditorView. `rotation` is used as a
/// per-state tag (CanvasState's own `==` only compares annotation ids, so the
/// tests assert on the returned state's fields instead).
final class CanvasHistoryTests: XCTestCase {

    private func state(_ tag: CGFloat) -> CanvasState {
        CanvasState(annotations: [], currentTool: .arrow, selectedAnnotationId: nil, rotation: tag)
    }

    func testStartsEmpty() {
        let h = CanvasHistory()
        XCTAssertFalse(h.canUndo)
        XCTAssertFalse(h.canRedo)
    }

    func testRecordEnablesUndoAndClearsRedoState() {
        var h = CanvasHistory()
        h.record(state(1))
        XCTAssertTrue(h.canUndo)
        XCTAssertFalse(h.canRedo)
    }

    func testUndoReturnsPreviousAndEnablesRedo() {
        var h = CanvasHistory()
        h.record(state(1))
        let applied = h.undo(current: state(2))
        XCTAssertEqual(applied?.rotation, 1)
        XCTAssertTrue(h.canRedo)
        XCTAssertFalse(h.canUndo)
    }

    func testRedoReturnsSwappedState() {
        var h = CanvasHistory()
        h.record(state(1))
        _ = h.undo(current: state(2))         // redo now holds the "2" state
        let redone = h.redo(current: state(1))
        XCTAssertEqual(redone?.rotation, 2)
        XCTAssertTrue(h.canUndo)
    }

    func testRecordingClearsRedoStack() {
        var h = CanvasHistory()
        h.record(state(1))
        _ = h.undo(current: state(2))
        XCTAssertTrue(h.canRedo)
        h.record(state(3))
        XCTAssertFalse(h.canRedo)
    }

    func testUndoRedoOnEmptyReturnNil() {
        var h = CanvasHistory()
        XCTAssertNil(h.undo(current: state(1)))
        XCTAssertNil(h.redo(current: state(1)))
    }

    func testCapDropsOldestStates() {
        var h = CanvasHistory(limit: 3)
        for i in 1...5 { h.record(state(CGFloat(i))) }   // retains 3,4,5
        XCTAssertEqual(h.undo(current: state(99))?.rotation, 5)
        XCTAssertEqual(h.undo(current: state(98))?.rotation, 4)
        XCTAssertEqual(h.undo(current: state(97))?.rotation, 3)
        XCTAssertNil(h.undo(current: state(0)))          // 1 and 2 were dropped
    }
}
