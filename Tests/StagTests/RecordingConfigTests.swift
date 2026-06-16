import XCTest
import CoreGraphics
@testable import Stag

/// `RecordingConfig.from(preferences:targetSize:captureRect:)` derives the recorder
/// settings from user preferences. FPS comes straight from the quality preset and
/// bit-rate scales with both pixel count and the quality multiplier.
final class RecordingConfigTests: XCTestCase {

    private func prefs(_ configure: (Preferences) -> Void) -> Preferences {
        let p = Preferences()
        configure(p)
        return p
    }

    func testFPSFollowsQualityPreset() {
        let size = CGSize(width: 640, height: 480)
        XCTAssertEqual(RecordingConfig.from(preferences: prefs { $0.recordingQuality = .low }, targetSize: size).fps, 15)
        XCTAssertEqual(RecordingConfig.from(preferences: prefs { $0.recordingQuality = .medium }, targetSize: size).fps, 30)
        XCTAssertEqual(RecordingConfig.from(preferences: prefs { $0.recordingQuality = .high }, targetSize: size).fps, 60)
    }

    func testBitRateScalesWithQualityMultiplier() {
        let size = CGSize(width: 1280, height: 720)
        let low = RecordingConfig.from(preferences: prefs { $0.recordingQuality = .low }, targetSize: size).bitRate
        let med = RecordingConfig.from(preferences: prefs { $0.recordingQuality = .medium }, targetSize: size).bitRate
        let high = RecordingConfig.from(preferences: prefs { $0.recordingQuality = .high }, targetSize: size).bitRate
        // multipliers are 2 / 4 / 8 → medium = 2×low, high = 4×low (scale factor cancels)
        XCTAssertEqual(med, low * 2)
        XCTAssertEqual(high, low * 4)
        XCTAssertGreaterThan(low, 0)
    }

    func testBitRateGrowsWithResolution() {
        let small = RecordingConfig.from(preferences: prefs { $0.recordingQuality = .high },
                                         targetSize: CGSize(width: 320, height: 240)).bitRate
        let large = RecordingConfig.from(preferences: prefs { $0.recordingQuality = .high },
                                         targetSize: CGSize(width: 1920, height: 1080)).bitRate
        XCTAssertGreaterThan(large, small)
    }

    func testPassesThroughPreferenceFlagsAndCaptureRect() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 200)
        let p = prefs {
            $0.recordSystemAudio = true
            $0.recordMicrophone = false
            $0.showCursorInRecording = false
            $0.webcamEnabled = true
            $0.webcamPosition = .topLeft
            $0.webcamSize = .small
            $0.showMouseClicks = true
        }
        let cfg = RecordingConfig.from(preferences: p, targetSize: CGSize(width: 800, height: 600), captureRect: rect)
        XCTAssertTrue(cfg.captureSystemAudio)
        XCTAssertFalse(cfg.captureMicrophone)
        XCTAssertFalse(cfg.showCursor)
        XCTAssertTrue(cfg.webcamEnabled)
        XCTAssertEqual(cfg.webcamPosition, .topLeft)
        XCTAssertEqual(cfg.webcamSize, .small)
        XCTAssertTrue(cfg.showMouseClicks)
        XCTAssertEqual(cfg.captureRect, rect)
        XCTAssertEqual(cfg.outputSize, CGSize(width: 800, height: 600))
    }

    func testCaptureRectDefaultsToNil() {
        let cfg = RecordingConfig.from(preferences: Preferences(), targetSize: CGSize(width: 100, height: 100))
        XCTAssertNil(cfg.captureRect)
    }
}
