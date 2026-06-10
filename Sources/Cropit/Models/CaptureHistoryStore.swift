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

    var dimensions: CGSize { CGSize(width: imageWidth, height: imageHeight) }

    init(image: NSImage, type: CaptureType, saveURL: URL, thumbnailURL: URL) {
        self.id = UUID()
        self.date = Date()
        self.type = type
        self.filePath = saveURL.path
        self.thumbnailPath = thumbnailURL.path
        self.imageWidth = Int(image.size.width)
        self.imageHeight = Int(image.size.height)
        self.fileSize = Int64((try? Data(contentsOf: saveURL).count) ?? 0)
        self.ocrText = nil
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
        let myShotDir = appSupport.appendingPathComponent("Cropit")
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
        let maxDim: CGFloat = 320
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return }
        let scale = min(maxDim / w, maxDim / h, 1.0)
        let thumbSize = CGSize(width: w * scale, height: h * scale)
        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        thumb.unlockFocus()
        let props: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 0.7]
        guard let tiff = thumb.tiffRepresentation,
              let bm = NSBitmapImageRep(data: tiff),
              let data = bm.representation(using: .jpeg, properties: props) else { return }
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

    // MARK: - Persistence

    private static let saveQueue = DispatchQueue(label: "com.ganwar.Cropit.historySave", qos: .utility)

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
