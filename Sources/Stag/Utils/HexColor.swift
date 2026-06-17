import SwiftUI
import AppKit

/// Formats colors as `#RRGGBB` hex strings. The eyedropper and the color-code
/// readout in the editor each built this string inline; centralizing it removes
/// the duplication and makes the formatting unit-testable.
enum HexColor {

    /// `#RRGGBB` from 8-bit channel values (each expected in 0...255).
    static func string(r: Int, g: Int, b: Int) -> String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    /// `#RRGGBB` for a SwiftUI color, sampled in sRGB. Channels are truncated to
    /// 8-bit (matching the previous inline behavior).
    static func string(from color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return string(r: Int(ns.redComponent * 255),
                      g: Int(ns.greenComponent * 255),
                      b: Int(ns.blueComponent * 255))
    }
}
