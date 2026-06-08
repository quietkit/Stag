import Foundation
import ScreenCaptureKit

enum RecorderState: Equatable {
    case idle
    case recording
    case finished(URL)
}

protocol CaptureRecorder: AnyObject {
    var recorderState: RecorderState { get }
    var outputURL: URL { get }
    var stream: SCStream? { get set }
    var processingQueue: DispatchQueue { get }

    func startCapture(filter: SCContentFilter, config: RecordingConfig, outputURL: URL) async throws
    func stopCapture() async -> URL?
    func cleanup()
}
