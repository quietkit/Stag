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
    let imageWidth: Int
    let imageHeight: Int
    let fileSize: Int64
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
