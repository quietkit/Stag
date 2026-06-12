import Foundation

enum CaptureError: LocalizedError {
    case screenRecordingPermissionDenied
    case captureFailed(reason: String)
    case captureCancelled
    case noActiveCapture
    case unsupportedFeature(String)
    case storageError
    case exportFailed(reason: String)
    case unsupportedFormat(String)
    case invalidSelection
    case historySaveFailed
    case preferenceLoadFailed

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionDenied: return "Screen Recording Permission Required"
        case .captureFailed(let r): return "Capture Failed: \(r)"
        case .captureCancelled: return "Capture Cancelled"
        case .noActiveCapture: return "No Active Capture"
        case .unsupportedFeature(let f): return "Unsupported Feature: \(f)"
        case .storageError: return "Storage Error"
        case .exportFailed(let r): return "Export Failed: \(r)"
        case .unsupportedFormat(let f): return "Unsupported Format: \(f)"
        case .invalidSelection: return "Invalid Selection"
        case .historySaveFailed: return "Could Not Save Capture History"
        case .preferenceLoadFailed: return "Could Not Load Preferences"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            return "1. Open System Settings → Privacy & Security → Screen Recording\n2. Click the + button and add Stag from the Applications or build folder\n3. Check the checkbox next to Stag\n4. Quit and relaunch the app"
        case .captureFailed:
            return "An unknown error occurred."
        case .captureCancelled:
            return "The capture was cancelled."
        case .noActiveCapture:
            return "No active capture to cancel."
        case .unsupportedFeature(let feature):
            return "\(feature) is not yet supported."
        case .storageError:
            return "Check disk space and permissions in ~/Library/Application Support/Stag/"
        default:
            return nil
        }
    }
}
