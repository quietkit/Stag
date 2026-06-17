import Cocoa

extension HotKeyCombination {
    /// Human-readable shortcut string, e.g. "⇧⌘1". Modifiers are emitted in the
    /// macOS-standard order (⌃⌥⇧⌘) followed by the key label. Returns "" when no
    /// key is set (keyCode 0); callers present their own placeholder there.
    var displayString: String {
        guard keyCode != 0 else { return "" }
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { parts.append("\u{2303}") }   // ⌃
        if flags.contains(.option)  { parts.append("\u{2325}") }   // ⌥
        if flags.contains(.shift)   { parts.append("\u{21E7}") }   // ⇧
        if flags.contains(.command) { parts.append("\u{2318}") }   // ⌘
        parts.append(Self.keyName(keyCode))
        return parts.joined()
    }

    /// Maps a macOS ANSI virtual keycode to its display label. Unknown codes fall
    /// back to "Key<code>".
    static func keyName(_ code: UInt16) -> String {
        keyNames[code] ?? "Key\(code)"
    }

    /// True macOS ANSI keycodes (NOT sequential — e.g. kVK_ANSI_5 = 23, _6 = 22).
    private static let keyNames: [UInt16: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
        26: "7", 28: "8", 25: "9", 29: "0",
        24: "=", 27: "-",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "T", 17: "Y",
        32: "U", 34: "I", 31: "O", 35: "P",
        0:  "A", 1:  "S", 2:  "D", 3:  "F", 4:  "H", 5:  "G",
        38: "J", 40: "K", 37: "L",
        45: "N", 46: "M",
        6:  "Z", 7:  "X", 8:  "C", 9:  "V", 11: "B",
        49: "Space",
        36: "Return", 53: "Esc", 48: "Tab", 51: "Delete",
    ]
}
