import Cocoa

/// Pure input rule for the editor's single-key tool rebinding, extracted from
/// EditorKeyCapture so the accept/translate decision can be tested without an
/// NSEvent monitor.
enum EditorToolKey {
    /// Valid binding characters: alphanumerics plus a handful of punctuation keys.
    private static let valid = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-=[];',./\\`"))

    /// Translates a key press into a tool-binding string, or `nil` to ignore it.
    /// Lowercases the character, rejects empty/invalid input, and prefixes "⇧"
    /// when Shift — and only Shift — is held.
    static func binding(char: String, modifiers: NSEvent.ModifierFlags) -> String? {
        let mods = modifiers.intersection(.deviceIndependentFlagsMask)
        let lower = char.lowercased()
        guard !lower.isEmpty,
              lower.unicodeScalars.allSatisfy({ valid.contains($0) }) else { return nil }
        return mods == .shift ? "\u{21E7}\(lower)" : lower
    }
}

/// Pure rule for recording a global hotkey, extracted from ShortcutCapture.
enum HotKeyCaptureRule {
    /// Builds the combination to record from a keyDown's keyCode + modifiers, or
    /// `nil` to ignore it. Requires at least one device-independent modifier, so
    /// bare keys can't be bound as global shortcuts.
    static func combination(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> HotKeyCombination? {
        let mods = modifiers.intersection(.deviceIndependentFlagsMask)
        guard !mods.isEmpty else { return nil }
        return HotKeyCombination(keyCode: keyCode, modifiers: mods.rawValue)
    }
}
