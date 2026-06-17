import SwiftUI

/// Most-recently-used color list logic for the editor's swatch row. Previously
/// this de-dup/insert/cap sequence lived inline in `EditorView`; extracting it
/// makes the rule a pure, unit-testable function and trims the view's surface.
enum RecentColors {
    /// Default number of swatches retained.
    static let limit = 8

    /// Returns `history` with `color` moved to the front (de-duplicated) and the
    /// list capped at `limit` — most-recently-used first.
    static func recording(_ color: Color, into history: [Color], limit: Int = limit) -> [Color] {
        var out = history
        out.removeAll { $0 == color }
        out.insert(color, at: 0)
        if out.count > limit {
            out.removeLast(out.count - limit)
        }
        return out
    }
}
