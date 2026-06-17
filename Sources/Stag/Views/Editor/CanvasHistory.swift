import Foundation

/// Bounded undo/redo history for the editor's annotation canvas. Owns the two
/// `CanvasState` stacks that previously lived as loose `@State` arrays inside
/// `EditorView`, along with the push/cap/clear-redo rule. Recording a new state
/// clears the redo stack; `undo`/`redo` swap the supplied "current" state across
/// the stacks and return the state the caller should apply (or `nil`).
struct CanvasHistory {
    private(set) var undoStack: [CanvasState] = []
    private(set) var redoStack: [CanvasState] = []
    let limit: Int

    init(limit: Int = 100) { self.limit = limit }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Pushes a snapshot onto the undo stack (capped at `limit`) and clears redo.
    mutating func record(_ state: CanvasState) {
        undoStack.append(state)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    /// Pops the previous state, pushing `current` onto the redo stack. Returns the
    /// state to apply, or `nil` when there is nothing to undo.
    mutating func undo(current: CanvasState) -> CanvasState? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Pops the next redo state, pushing `current` onto the undo stack. Returns the
    /// state to apply, or `nil` when there is nothing to redo.
    mutating func redo(current: CanvasState) -> CanvasState? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
