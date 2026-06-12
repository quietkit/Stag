import Cocoa

enum URLCommand {
    case capture(type: CaptureType?, delay: TimeInterval)
    case preferences
    case history
    case pinboard
}

struct URLSchemeHandler {
    static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme == "stag" else { return nil }

        switch url.host?.lowercased() {
        case "capture", "capture-area":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let query = components?.queryItems ?? []

            let type: CaptureType? = {
                guard let raw = query.first(where: { $0.name == "type" })?.value?.lowercased() else {
                    return url.host == "capture-area" ? .area : nil
                }
                return CaptureType(rawValue: raw)
            }()

            let delay: TimeInterval = {
                guard let raw = query.first(where: { $0.name == "delay" })?.value else { return 0 }
                return TimeInterval(raw) ?? 0
            }()

            return .capture(type: type, delay: delay)

        case "preferences", "settings":
            return .preferences

        case "history":
            return .history

        case "pinboard":
            return .pinboard

        default:
            return nil
        }
    }
}
