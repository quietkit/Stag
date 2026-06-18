import Cocoa
import Combine

// MARK: - Record Types

enum CaptureType: String, Codable, CaseIterable {
    case area, window, fullscreen, scrolling, recording, gif

    var isScreenCapture: Bool {
        switch self {
        case .area, .window, .fullscreen, .scrolling: return true
        case .recording, .gif: return false
        }
    }
}

struct CaptureRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let type: CaptureType
    let filePath: String
    let thumbnailPath: String
    var imageWidth: Int
    var imageHeight: Int
    var fileSize: Int64
    var ocrText: String?
    var appName: String?      // frontmost app at capture time
    var isFavorite: Bool      // starred by user

    var dimensions: CGSize { CGSize(width: imageWidth, height: imageHeight) }

    init(image: NSImage, type: CaptureType, saveURL: URL, thumbnailURL: URL, appName: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.type = type
        self.filePath = saveURL.path
        self.thumbnailPath = thumbnailURL.path
        self.imageWidth = Int(image.size.width)
        self.imageHeight = Int(image.size.height)
        self.fileSize = Int64((try? Data(contentsOf: saveURL).count) ?? 0)
        self.ocrText = nil
        self.appName = appName
        self.isFavorite = false
    }

    // Codable with backward-compatible defaults
    private enum CodingKeys: String, CodingKey {
        case id, date, type, filePath, thumbnailPath
        case imageWidth, imageHeight, fileSize, ocrText
        case appName, isFavorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self, forKey: .id)
        date          = try c.decode(Date.self, forKey: .date)
        type          = try c.decode(CaptureType.self, forKey: .type)
        filePath      = try c.decode(String.self, forKey: .filePath)
        thumbnailPath = try c.decode(String.self, forKey: .thumbnailPath)
        imageWidth    = try c.decode(Int.self, forKey: .imageWidth)
        imageHeight   = try c.decode(Int.self, forKey: .imageHeight)
        fileSize      = try c.decode(Int64.self, forKey: .fileSize)
        ocrText       = try c.decodeIfPresent(String.self, forKey: .ocrText)
        appName       = try c.decodeIfPresent(String.self, forKey: .appName)
        isFavorite    = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

// MARK: - History Store

final class CaptureHistoryStore: ObservableObject {
    @Published var records: [CaptureRecord] = []
    @Published var searchQuery = ""

    private let storageURL: URL
    private let maxRecords = 1000
    private var cancellables = Set<AnyCancellable>()

    var filteredRecords: [CaptureRecord] {
        guard !searchQuery.isEmpty else { return records }
        let q = searchQuery.lowercased()
        return records.filter { record in
            if record.ocrText?.localizedCaseInsensitiveContains(q) == true { return true }
            if record.appName?.localizedCaseInsensitiveContains(q) == true { return true }
            let filename = (record.filePath as NSString).lastPathComponent.lowercased()
            if filename.contains(q) { return true }
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            if fmt.string(from: record.date).lowercased().contains(q) { return true }
            return false
        }
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let myShotDir = appSupport.appendingPathComponent("Stag")
        try? FileManager.default.createDirectory(at: myShotDir, withIntermediateDirectories: true)
        storageURL = myShotDir.appendingPathComponent("capture_history.json")

        load()

        $searchQuery
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func add(_ record: CaptureRecord) {
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    func remove(_ id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func toggleFavorite(_ id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].isFavorite.toggle()
        save()
    }

    /// Called after the editor saves edits back to an existing capture file:
    /// regenerates the thumbnail and refreshes the record so the grid updates.
    func updateEditedImage(filePath: String, image: NSImage) {
        guard let idx = records.firstIndex(where: { $0.filePath == filePath }) else { return }
        var rec = records[idx]
        Self.writeThumbnail(image, to: URL(fileURLWithPath: rec.thumbnailPath))
        rec.imageWidth = Int(image.size.width)
        rec.imageHeight = Int(image.size.height)
        let byteCount = (try? Data(contentsOf: URL(fileURLWithPath: filePath)))?.count
        rec.fileSize = byteCount.map(Int64.init) ?? rec.fileSize
        records[idx] = rec    // re-emits @Published → cells re-read the new thumbnail
        save()
    }

    static func writeThumbnail(_ image: NSImage, to url: URL) {
        let thumbSize = ThumbnailGeometry.fittedSize(for: image.size, maxDimension: 320)
        guard thumbSize.width > 0 else { return }
        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        thumb.unlockFocus()
        guard let data = thumb.encoded(as: .jpeg(quality: 0.7)) else { return }
        try? data.write(to: url)
    }

    func removeAll() {
        records.removeAll()
        save()
    }

    func records(for type: CaptureType) -> [CaptureRecord] {
        records.filter { $0.type == type }
    }

    func records(since date: Date) -> [CaptureRecord] {
        records.filter { $0.date >= date }
    }

    /// Writes a JSON sidecar file next to the image, returns the sidecar URL.
    @discardableResult
    func exportMetadata(for record: CaptureRecord) -> URL? {
        let imageURL = URL(fileURLWithPath: record.filePath)
        let sidecarURL = imageURL.deletingPathExtension().appendingPathExtension("json")
        let payload: [String: Any?] = [
            "id":          record.id.uuidString,
            "date":        ISO8601DateFormatter().string(from: record.date),
            "type":        record.type.rawValue,
            "filePath":    record.filePath,
            "width":       record.imageWidth,
            "height":      record.imageHeight,
            "fileSize":    record.fileSize,
            "appName":     record.appName,
            "isFavorite":  record.isFavorite,
            "ocrText":     record.ocrText,
        ]
        let cleaned = payload.compactMapValues { $0 }
        guard let data = try? JSONSerialization.data(withJSONObject: cleaned,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return nil }
        try? data.write(to: sidecarURL, options: .atomic)
        return sidecarURL
    }

    // MARK: - Persistence

    private static let saveQueue = DispatchQueue(label: "com.ganwar.Stag.historySave", qos: .utility)

    private func save() {
        let snapshot = records
        let url = storageURL
        Self.saveQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([CaptureRecord].self, from: data)
        else { return }
        records = decoded
    }
}
