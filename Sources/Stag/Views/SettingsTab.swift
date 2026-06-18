import SwiftUI

/// The panes of the Settings window. Owns each tab's presentation metadata —
/// sidebar icon/tint/label and the page subtitle — lifted out of PreferencesView
/// so the mapping is a plain, testable value type rather than view-private code.
enum SettingsTab: String, CaseIterable {
    case general, capture, recording, overlays, shortcuts, advanced

    var icon: String {
        switch self {
        case .general:   return "gearshape.fill"
        case .capture:   return "camera.fill"
        case .recording: return "video.fill"
        case .overlays:  return "square.on.square"
        case .shortcuts: return "keyboard.fill"
        case .advanced:  return "wrench.and.screwdriver.fill"
        }
    }

    var label: String {
        switch self {
        case .general:   return "General"
        case .capture:   return "Capture"
        case .recording: return "Recording"
        case .overlays:  return "Overlays"
        case .shortcuts: return "Shortcuts"
        case .advanced:  return "Advanced"
        }
    }

    var tint: Color {
        switch self {
        case .general:   return .gray
        case .capture:   return .blue
        case .recording: return .red
        case .overlays:  return .purple
        case .shortcuts: return .orange
        case .advanced:  return .teal
        }
    }

    var subtitle: String {
        switch self {
        case .general:   return "Output format, saving, and after-capture behavior."
        case .capture:   return "Timer, preparation, and selection behavior."
        case .recording: return "Video quality, audio, and recording overlays."
        case .overlays:  return "Webcam picture-in-picture and click effects."
        case .shortcuts: return "Global hotkeys and editor tool keys."
        case .advanced:  return "Automation URL scheme and custom upload endpoint."
        }
    }
}
