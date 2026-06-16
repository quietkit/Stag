import XCTest
import AppKit
import SwiftUI
@testable import Stag

/// Exercises the pure value types and their computed properties: capture/format
/// enums, the editor styling enums, error messages, and the app-state equality.
/// All of this is platform-logic with no display, capture, or permission needs.
final class ValueTypeTests: XCTestCase {

    // MARK: - CaptureFormat / AfterCaptureAction

    func testCaptureFormatRawValuesRoundTrip() {
        for c in CaptureFormat.allCases {
            XCTAssertEqual(CaptureFormat(rawValue: c.rawValue), c)
        }
        XCTAssertEqual(CaptureFormat.allCases, [.png, .jpeg])
    }

    func testAfterCaptureActionRawValuesRoundTrip() {
        for c in AfterCaptureAction.allCases {
            XCTAssertEqual(AfterCaptureAction(rawValue: c.rawValue), c)
        }
        XCTAssertTrue(AfterCaptureAction.allCases.contains(.openEditor))
    }

    // MARK: - ThumbnailPosition / ThumbnailSize

    func testThumbnailPositionDisplayNames() {
        XCTAssertEqual(ThumbnailPosition.bottomRight.displayName, "Bottom Right")
        XCTAssertEqual(ThumbnailPosition.bottomLeft.displayName, "Bottom Left")
        XCTAssertEqual(ThumbnailPosition.topRight.displayName, "Top Right")
        XCTAssertEqual(ThumbnailPosition.topLeft.displayName, "Top Left")
        // every case must yield a non-empty label
        for c in ThumbnailPosition.allCases { XCTAssertFalse(c.displayName.isEmpty) }
    }

    func testThumbnailSizeIsMonotonic() {
        let s = ThumbnailSize.small.size, m = ThumbnailSize.medium.size, l = ThumbnailSize.large.size
        XCTAssertLessThan(s.width, m.width)
        XCTAssertLessThan(m.width, l.width)
        XCTAssertLessThan(s.height, m.height)
        XCTAssertLessThan(m.height, l.height)
        XCTAssertEqual(s, CGSize(width: 160, height: 100))
        XCTAssertEqual(l, CGSize(width: 300, height: 190))
    }

    // MARK: - RecordingQuality

    func testRecordingQualityFPS() {
        XCTAssertEqual(RecordingQuality.low.fps, 15)
        XCTAssertEqual(RecordingQuality.medium.fps, 30)
        XCTAssertEqual(RecordingQuality.high.fps, 60)
        XCTAssertLessThan(RecordingQuality.low.fps, RecordingQuality.high.fps)
    }

    // MARK: - Webcam enums

    func testWebcamPositionDisplayNames() {
        XCTAssertEqual(WebcamPosition.topLeft.displayName, "Top Left")
        XCTAssertEqual(WebcamPosition.bottomRight.displayName, "Bottom Right")
        for c in WebcamPosition.allCases { XCTAssertFalse(c.displayName.isEmpty) }
    }

    func testWebcamSizeIsMonotonic() {
        XCTAssertLessThan(WebcamSize.small.size.width, WebcamSize.large.size.width)
        XCTAssertEqual(WebcamSize.medium.size, CGSize(width: 240, height: 180))
    }

    // MARK: - CaptureType

    func testCaptureTypeIsScreenCapture() {
        XCTAssertTrue(CaptureType.area.isScreenCapture)
        XCTAssertTrue(CaptureType.window.isScreenCapture)
        XCTAssertTrue(CaptureType.fullscreen.isScreenCapture)
        XCTAssertTrue(CaptureType.scrolling.isScreenCapture)
        XCTAssertFalse(CaptureType.recording.isScreenCapture)
        XCTAssertFalse(CaptureType.gif.isScreenCapture)
    }

    // MARK: - HotKeyCombination

    func testHotKeyDefaultsCoverEveryCaptureType() {
        let defaults = HotKeyCombination.default()
        for type in CaptureType.allCases {
            XCTAssertNotNil(defaults[type], "missing default hotkey for \(type)")
        }
    }

    func testHotKeyRecordAndGifKeycodesAreNotSwapped() {
        // Regression guard: ⌘⇧5 = Record (keyCode 23), ⌘⇧6 = GIF (keyCode 22).
        let defaults = HotKeyCombination.default()
        XCTAssertEqual(defaults[.recording]?.keyCode, 23)
        XCTAssertEqual(defaults[.gif]?.keyCode, 22)
    }

    func testHotKeyModifierFlagsDeriveFromRawValue() {
        let cmdShift: UInt = NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
        let combo = HotKeyCombination(keyCode: 18, modifiers: cmdShift)
        XCTAssertTrue(combo.modifierFlags.contains(.command))
        XCTAssertTrue(combo.modifierFlags.contains(.shift))
        XCTAssertFalse(combo.modifierFlags.contains(.option))
    }

    func testHotKeyCombinationCodableRoundTrip() throws {
        let combo = HotKeyCombination(keyCode: 42, modifiers: 7)
        let data = try JSONEncoder().encode(combo)
        let decoded = try JSONDecoder().decode(HotKeyCombination.self, from: data)
        XCTAssertEqual(combo, decoded)
    }

    // MARK: - Editor enums

    func testLineStyleDashPatterns() {
        XCTAssertEqual(LineStyle.solid.dashPattern, [])
        XCTAssertEqual(LineStyle.dashed.dashPattern, [6, 4])
        XCTAssertEqual(LineStyle.dotted.dashPattern, [2, 3])
        for c in LineStyle.allCases { XCTAssertFalse(c.displayName.isEmpty) }
    }

    func testArrowHeadStyleDisplayNames() {
        XCTAssertEqual(ArrowHeadStyle.standard.displayName, "Standard")
        XCTAssertEqual(ArrowHeadStyle.filled.displayName, "Filled")
        XCTAssertEqual(ArrowHeadStyle.circle.displayName, "Circle")
    }

    func testBackdropKindDisplayNames() {
        XCTAssertEqual(BackdropKind.none.displayName, "None")
        XCTAssertEqual(BackdropKind.gradient.displayName, "Gradient")
        for c in BackdropKind.allCases { XCTAssertFalse(c.displayName.isEmpty) }
    }

    func testTextStyleWeightAndDesign() {
        XCTAssertEqual(TextStyle.bold.weight, .semibold)
        XCTAssertEqual(TextStyle.boldItalic.weight, .semibold)
        XCTAssertEqual(TextStyle.regular.weight, .regular)
        XCTAssertNil(TextStyle.regular.design)
        XCTAssertNotNil(TextStyle.italic.design)
    }

    func testDrawingToolRawValuesAreUnique() {
        let raws = DrawingTool.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "DrawingTool raw values must be unique")
    }

    // MARK: - CaptureError

    func testCaptureErrorDescriptionsArePresent() {
        let cases: [CaptureError] = [
            .screenRecordingPermissionDenied,
            .captureFailed(reason: "boom"),
            .captureCancelled, .noActiveCapture,
            .unsupportedFeature("PDF"), .storageError,
            .exportFailed(reason: "disk"), .unsupportedFormat("bmp"),
            .invalidSelection, .historySaveFailed, .preferenceLoadFailed,
        ]
        for e in cases {
            XCTAssertFalse((e.errorDescription ?? "").isEmpty, "missing description for \(e)")
        }
    }

    func testCaptureErrorInterpolatesAssociatedValues() {
        XCTAssertEqual(CaptureError.captureFailed(reason: "boom").errorDescription, "Capture Failed: boom")
        XCTAssertEqual(CaptureError.unsupportedFormat("bmp").errorDescription, "Unsupported Format: bmp")
    }

    func testCaptureErrorRecoverySuggestions() {
        XCTAssertNotNil(CaptureError.screenRecordingPermissionDenied.recoverySuggestion)
        XCTAssertEqual(CaptureError.unsupportedFeature("PDF").recoverySuggestion, "PDF is not yet supported.")
        // The `default` branch returns nil for errors without a tailored hint.
        XCTAssertNil(CaptureError.invalidSelection.recoverySuggestion)
        XCTAssertNil(CaptureError.exportFailed(reason: "x").recoverySuggestion)
    }

    // MARK: - CaptureState equality

    func testCaptureStateEquality() {
        XCTAssertEqual(CaptureState.idle, .idle)
        XCTAssertEqual(CaptureState.selecting, .selecting)
        XCTAssertNotEqual(CaptureState.idle, .capturing)
        XCTAssertEqual(CaptureState.error(.storageError), .error(.storageError))
        XCTAssertNotEqual(CaptureState.error(.storageError), .error(.invalidSelection))
        XCTAssertNotEqual(CaptureState.completed, .processing)
    }
}
