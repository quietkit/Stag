import XCTest
import AppKit
@testable import Stag

/// Round-trips `Preferences` through its `UserDefaults` JSON store and verifies the
/// derived values and migrations. The existing value under the prefs key is backed
/// up and restored so a developer's real settings survive a local test run.
final class PreferencesPersistenceTests: XCTestCase {

    private var backup: Data?

    override func setUp() {
        super.setUp()
        backup = UserDefaults.standard.data(forKey: Preferences.defaultsKey)
        UserDefaults.standard.removeObject(forKey: Preferences.defaultsKey)
    }

    override func tearDown() {
        if let backup {
            UserDefaults.standard.set(backup, forKey: Preferences.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Preferences.defaultsKey)
        }
        super.tearDown()
    }

    func testFreshDefaults() {
        let p = Preferences()
        XCTAssertEqual(p.defaultFormat, .png)
        XCTAssertEqual(p.jpegQuality, 0.9, accuracy: 0.0001)
        XCTAssertEqual(p.filePrefix, "Stag_")
        XCTAssertEqual(p.afterCaptureAction, .openEditor)
        XCTAssertTrue(p.autoCopyToClipboard)
        XCTAssertTrue(p.directCapture)
        XCTAssertTrue(p.useSmartFilenames)
    }

    func testSaveLoadRoundTrip() {
        let p = Preferences()
        p.defaultFormat = .jpeg
        p.jpegQuality = 0.5
        p.savePath = "~/Pictures/Stag"
        p.filePrefix = "Cap_"
        p.afterCaptureAction = .copy
        p.autoCopyToClipboard = false
        p.recordingQuality = .low
        p.webcamSize = .large
        p.save()

        let q = Preferences()
        XCTAssertEqual(q.defaultFormat, .jpeg)
        XCTAssertEqual(q.jpegQuality, 0.5, accuracy: 0.0001)
        XCTAssertEqual(q.savePath, "~/Pictures/Stag")
        XCTAssertEqual(q.filePrefix, "Cap_")
        XCTAssertEqual(q.afterCaptureAction, .copy)
        XCTAssertFalse(q.autoCopyToClipboard)
        XCTAssertEqual(q.recordingQuality, .low)
        XCTAssertEqual(q.webcamSize, .large)
    }

    func testExpandedSavePathExpandsTilde() {
        let p = Preferences()
        p.savePath = "~/Desktop/Shots"
        let expanded = p.expandedSavePath
        XCTAssertFalse(expanded.hasPrefix("~"))
        XCTAssertTrue(expanded.hasSuffix("/Desktop/Shots"))
    }

    func testUploadConfigDerivedFromFields() {
        let p = Preferences()
        p.uploadURL = "https://up.example/api"
        p.uploadMethod = "PUT"
        p.uploadFieldName = "image"
        p.uploadHeaders = "Authorization: Bearer xyz\nX-Test: 1"
        p.uploadResponseKey = "data.url"

        let cfg = p.uploadConfig
        XCTAssertEqual(cfg.endpoint, "https://up.example/api")
        XCTAssertEqual(cfg.method, "PUT")
        XCTAssertEqual(cfg.fieldName, "image")
        XCTAssertEqual(cfg.responseURLKey, "data.url")
        XCTAssertEqual(cfg.headers["Authorization"], "Bearer xyz")
        XCTAssertEqual(cfg.headers["X-Test"], "1")
        XCTAssertTrue(cfg.isConfigured)
    }

    func testSwappedRecordGifKeycodesAreMigratedOnLoad() {
        let cmdShift: UInt = NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
        let p = Preferences()
        // Simulate the historical bug: Record bound to keyCode 22, GIF to 23.
        p.hotkeys[.recording] = HotKeyCombination(keyCode: 22, modifiers: cmdShift)
        p.hotkeys[.gif] = HotKeyCombination(keyCode: 23, modifiers: cmdShift)
        p.save()

        let q = Preferences()  // load() should correct the swap
        XCTAssertEqual(q.hotkeys[.recording]?.keyCode, 23)
        XCTAssertEqual(q.hotkeys[.gif]?.keyCode, 22)
    }

    func testEditorHotkeysPersist() {
        let p = Preferences()
        p.editorHotkeys["arrow"] = "a"
        p.save()
        let q = Preferences()
        XCTAssertEqual(q.editorHotkeys["arrow"], "a")
    }
}
