import Foundation

/// Bounded undo/redo history for editor state. Owns two stacks of snapshots and
/// the push/cap/clear-redo and pop/swap rules that previously lived as loose
/// `@State` arrays inside `EditorView`. Recording a new snapshot clears the redo
/// stack; `undo`/`redo` swap the supplied "current" snapshot across the stacks
/// and return the snapshot the caller should apply (or `nil`).
struct BoundedHistory<Snapshot> {
    private(set) var undoStack: [Snapshot] = []
    private(set) var redoStack: [Snapshot] = []
    let limit: Int

    init(limit: Int = 100) { self.limit = limit }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Pushes a snapshot onto the undo stack (capped at `limit`) and clears redo.
    mutating func record(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    /// Pops the previous snapshot, pushing `current` onto the redo stack. Returns
    /// the snapshot to apply, or `nil` when there is nothing to undo.
    mutating func undo(current: Snapshot) -> Snapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Pops the next redo snapshot, pushing `current` onto the undo stack. Returns
    /// the snapshot to apply, or `nil` when there is nothing to redo.
    mutating func redo(current: Snapshot) -> Snapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}

/// The editor's annotation-canvas undo/redo history.
typealias CanvasHistory = BoundedHistory<CanvasState>
