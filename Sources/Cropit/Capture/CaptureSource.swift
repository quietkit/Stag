import Cocoa

enum CaptureOutput {
    case image(CGImage)
    case video(URL)
}

protocol CaptureSource: AnyObject {
    var type: CaptureType { get }
    func beginCapture(store: AppStore) async throws -> CaptureOutput
}
