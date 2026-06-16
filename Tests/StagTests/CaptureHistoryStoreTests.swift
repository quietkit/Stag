import XCTest
import AppKit
@testable import Stag

/// `CaptureRecord` (de)serialization plus the in-memory query/filter helpers of
/// `CaptureHistoryStore`. Filtering operates on the `records` array directly, so
/// the tests set it in memory and never touch the on-disk history file. The
/// metadata sidecar and thumbnail writers are exercised against a temp directory.
final class CaptureHistoryStoreTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Builds a record backed by a real (tiny) file so `fileSize` resolves.
    private func makeRecord(filename: String = "shot.png",
                            type: CaptureType = .area,
                            appName: String? = nil,
                            ocrText: String? = nil,
                            size: NSSize = NSSize(width: 30, height: 20),
                            payload: Data = Data([0, 1, 2, 3])) -> CaptureRecord {
        let saveURL = tmp.appendingPathComponent(filename)
        try? payload.write(to: saveURL)
        let thumbURL = tmp.appendingPathComponent("thumb-\(filename).jpg")
        var rec = CaptureRecord(image: NSImage(size: size), type: type,
                                saveURL: saveURL, thumbnailURL: thumbURL, appName: appName)
        rec.ocrText = ocrText
        return rec
    }

    // MARK: - CaptureRecord

    func testRecordInitCapturesDimensionsAndFileSize() {
        let rec = makeRecord(payload: Data(repeating: 0xAB, count: 42))
        XCTAssertEqual(rec.imageWidth, 30)
        XCTAssertEqual(rec.imageHeight, 20)
        XCTAssertEqual(rec.fileSize, 42)
        XCTAssertFalse(rec.isFavorite)
        XCTAssertNil(rec.ocrText)
        XCTAssertEqual(rec.dimensions, CGSize(width: 30, height: 20))
    }

    func testRecordCodableRoundTrip() throws {
        let rec = makeRecord(appName: "Xcode", ocrText: "sample")
        let data = try JSONEncoder().encode(rec)
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: data)
        XCTAssertEqual(decoded, rec)
    }

    func testRecordDecodeAppliesBackwardCompatibleDefaults() throws {
        // Legacy payload missing isFavorite / ocrText / appName.
        let json = """
        {"id":"\(UUID().uuidString)","date":0,"type":"window",
         "filePath":"/tmp/a.png","thumbnailPath":"/tmp/a.jpg",
         "imageWidth":100,"imageHeight":50,"fileSize":1234}
        """
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.type, .window)
        XCTAssertFalse(decoded.isFavorite)   // defaulted
        XCTAssertNil(decoded.ocrText)
        XCTAssertNil(decoded.appName)
        XCTAssertEqual(decoded.imageWidth, 100)
    }

    // MARK: - filteredRecords

    func testFilteredRecordsEmptyQueryReturnsAll() {
        let store = CaptureHistoryStore()
        store.records = [makeRecord(filename: "a.png"), makeRecord(filename: "b.png")]
        store.searchQuery = ""
        XCTAssertEqual(store.filteredRecords.count, 2)
    }

    func testFilteredRecordsMatchesAppNameOCRAndFilename() {
        let store = CaptureHistoryStore()
        store.records = [
            makeRecord(filename: "one.png", appName: "Slack"),
            makeRecord(filename: "two.png", ocrText: "hello world"),
            makeRecord(filename: "special-token.png"),
        ]
        store.searchQuery = "slack"
        XCTAssertEqual(store.filteredRecords.count, 1)

        store.searchQuery = "HELLO"   // case-insensitive ocr match
        XCTAssertEqual(store.filteredRecords.count, 1)

        store.searchQuery = "special-token"
        XCTAssertEqual(store.filteredRecords.count, 1)

        store.searchQuery = "no-such-thing"
        XCTAssertTrue(store.filteredRecords.isEmpty)
    }

    // MARK: - records(for:) / records(since:)

    func testRecordsForType() {
        let store = CaptureHistoryStore()
        store.records = [makeRecord(filename: "a.png", type: .area),
                         makeRecord(filename: "b.png", type: .gif),
                         makeRecord(filename: "c.png", type: .area)]
        XCTAssertEqual(store.records(for: .area).count, 2)
        XCTAssertEqual(store.records(for: .gif).count, 1)
        XCTAssertTrue(store.records(for: .fullscreen).isEmpty)
    }

    func testRecordsSince() {
        let store = CaptureHistoryStore()
        store.records = [makeRecord()]
        XCTAssertEqual(store.records(since: .distantPast).count, 1)
        XCTAssertTrue(store.records(since: .distantFuture).isEmpty)
    }

    // MARK: - exportMetadata

    func testExportMetadataWritesValidJSONSidecar() throws {
        let store = CaptureHistoryStore()
        let rec = makeRecord(filename: "meta.png", appName: "Notes", ocrText: "scanned")
        let sidecar = try XCTUnwrap(store.exportMetadata(for: rec))
        XCTAssertEqual(sidecar.pathExtension, "json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any]
        XCTAssertEqual(obj?["appName"] as? String, "Notes")
        XCTAssertEqual(obj?["ocrText"] as? String, "scanned")
        XCTAssertEqual(obj?["type"] as? String, "area")
    }

    func testExportMetadataOmitsNilValues() throws {
        let store = CaptureHistoryStore()
        let rec = makeRecord(filename: "nil-meta.png")  // no appName, no ocr
        let sidecar = try XCTUnwrap(store.exportMetadata(for: rec))
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any]
        XCTAssertNil(obj?["appName"])
        XCTAssertNil(obj?["ocrText"])
    }

    // MARK: - writeThumbnail

    func testWriteThumbnailProducesAFile() throws {
        let url = tmp.appendingPathComponent("thumb.jpg")
        CaptureHistoryStore.writeThumbnail(NSImage(size: NSSize(width: 640, height: 480)), to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        XCTAssertGreaterThan(size ?? 0, 0)
    }

    func testWriteThumbnailIgnoresZeroSizedImage() {
        let url = tmp.appendingPathComponent("zero.jpg")
        CaptureHistoryStore.writeThumbnail(NSImage(size: .zero), to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
