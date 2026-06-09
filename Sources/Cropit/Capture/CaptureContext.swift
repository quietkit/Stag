import Cocoa

/// Carries lightweight context about *what* the user was looking at when a
/// capture was triggered, so saved files can be named meaningfully
/// (e.g. `Slack 2026-06-10T...png`) rather than by timestamp alone.
///
/// `sourceAppName` must be recorded at hotkey-dispatch time — BEFORE Cropit
/// activates itself — otherwise the frontmost app is already Cropit.
final class CaptureContext {
    static let shared = CaptureContext()
    private init() {}

    var sourceAppName: String?

    /// Records the currently-frontmost application as the capture source,
    /// ignoring Cropit itself.
    func recordFrontmostApp() {
        let name = NSWorkspace.shared.frontmostApplication?.localizedName
        if let name, name != "Cropit" { sourceAppName = name }
    }

    /// A filesystem-safe slug derived from the source app, or "" if none.
    /// e.g. "Google Chrome" → "Google Chrome", "Finder" → "Finder".
    func filenameSlug() -> String {
        guard let raw = sourceAppName else { return "" }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.unicodeScalars.filter { allowed.contains($0) }
        let slug = String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespaces)
        return String(slug.prefix(40))
    }
}
