import Foundation

/// Assembles capture filenames from their parts so the real save path
/// (`CaptureManager`) and the settings preview (`PreferencesWindow`) share one
/// rule and can't drift. Format: `<prefix><slug + space?><timestamp>.<ext>`.
enum CaptureFilename {
    /// Builds a capture filename. An empty `prefix` falls back to `"Stag_"`; an
    /// empty `slug` is omitted along with its separating space.
    static func make(prefix: String, slug: String, timestamp: String, ext: String) -> String {
        let resolvedPrefix = prefix.isEmpty ? "Stag_" : prefix
        let middle = slug.isEmpty ? "" : "\(slug) "
        return "\(resolvedPrefix)\(middle)\(timestamp).\(ext)"
    }
}
