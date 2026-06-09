import SwiftUI

private let historyDateFormatter1: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private let historyDateFormatter2: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()

struct HistoryBrowserView: View {
    @StateObject private var store = AppStore.shared.history
    @State private var filterType: CaptureType? = nil
    @State private var searchText = ""
    @State private var selectedId: UUID?
    @State private var hoveredId: UUID?

    private let columns = [GridItem(.fixed(180), spacing: 12)]

    private var filtered: [CaptureRecord] {
        let records = store.records
        let typed = filterType.map { t in records.filter { $0.type == t } } ?? records
        guard !searchText.isEmpty else { return typed }
        let query = searchText.lowercased()
        return typed.filter { r in
            if r.ocrText?.localizedCaseInsensitiveContains(query) == true { return true }
            let fn = (r.filePath as NSString).lastPathComponent.lowercased()
            if fn.contains(query) { return true }
            if historyDateFormatter1.string(from: r.date).contains(query) { return true }
            if historyDateFormatter2.string(from: r.date).lowercased().contains(query) { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                thumbnailGrid
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search captures\u{2026}", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                Text("\(filtered.count)/\(store.records.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            filterBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip("All", type: nil)
                ForEach(CaptureType.allCases, id: \.self) { t in
                    filterChip(typeLabel(t), type: t)
                }
            }
        }
    }

    private func filterChip(_ label: String, type: CaptureType?) -> some View {
        Button {
            withAnimation(.spring(response: 0.2)) { filterType = type }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: filterType == type ? .semibold : .regular))
                .foregroundColor(filterType == type ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(filterType == type ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No captures yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            Text("Take a screenshot and it will appear here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Thumbnail Grid

    private var thumbnailGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filtered) { record in
                    thumbnailCell(record)
                        .frame(maxWidth: .infinity)
                        .onTapGesture(count: 2) { openEditor(record) }
                        .onTapGesture { selectedId = record.id }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedId == record.id ? Color.accentColor.opacity(0.1) : .clear)
                        )
                }
            }
            .padding(16)
        }
    }

    private func thumbnailCell(_ record: CaptureRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                thumbnailImage(record)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180, height: 120)
                    .clipped()
                RoundedRectangle(cornerRadius: 8)
                    .stroke(hoveredId == record.id ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.1), lineWidth: 1)
                typeBadge(record.type)
                    .padding(4)
                    .alignmentGuide(.top) { _ in 0 }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { hoveredId = hovering ? record.id : nil }
            }
            .contextMenu { cellContextMenu(record) }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text("\(record.imageWidth) × \(record.imageHeight)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func thumbnailImage(_ record: CaptureRecord) -> some View {
        Group {
            if let image = NSImage(contentsOfFile: record.thumbnailPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let image = NSImage(contentsOfFile: record.filePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay(
                        Image(systemName: "questionmark")
                            .foregroundColor(.secondary)
                    )
            }
        }
    }

    private func typeBadge(_ type: CaptureType) -> some View {
        Text(typeShortLabel(type))
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(typeColor(type))
            .clipShape(Capsule())
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func cellContextMenu(_ record: CaptureRecord) -> some View {
        Button("Open in Editor", systemImage: "pencil") { openEditor(record) }
        Divider()
        Button("Reveal in Finder", systemImage: "folder") { revealInFinder(record) }
        Button("Copy Image", systemImage: "doc.on.doc") { copyImage(record) }
        if let ocr = record.ocrText, !ocr.isEmpty {
            Button("Copy OCR Text", systemImage: "text.viewfinder") { copyOCR(record) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { deleteRecord(record) }
    }

    // MARK: - Actions

    private func openEditor(_ record: CaptureRecord) {
        guard let image = NSImage(contentsOfFile: record.filePath) else { return }
        let editor = EditorWindow(image: image)
        editor.title = record.date.formatted(date: .abbreviated, time: .shortened)
        editor.show()
    }

    private func revealInFinder(_ record: CaptureRecord) {
        let url = URL(fileURLWithPath: record.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyImage(_ record: CaptureRecord) {
        guard let image = NSImage(contentsOfFile: record.filePath) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func copyOCR(_ record: CaptureRecord) {
        guard let text = record.ocrText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func deleteRecord(_ record: CaptureRecord) {
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: record.filePath), resultingItemURL: nil)
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: record.thumbnailPath), resultingItemURL: nil)
        store.remove(record.id)
    }

    // MARK: - Helpers

    private func typeLabel(_ type: CaptureType) -> String {
        switch type {
        case .area:      return "Area"
        case .window:    return "Window"
        case .fullscreen:return "Fullscreen"
        case .scrolling: return "Scrolling"
        case .recording: return "Recording"
        case .gif:       return "GIF"
        }
    }

    private func typeShortLabel(_ type: CaptureType) -> String {
        switch type {
        case .area:      return "⌗"
        case .window:    return "⊞"
        case .fullscreen:return "⬡"
        case .scrolling: return "⇟"
        case .recording: return "●"
        case .gif:       return "GIF"
        }
    }

    private func typeColor(_ type: CaptureType) -> Color {
        switch type {
        case .area:      return .blue
        case .window:    return .orange
        case .fullscreen:return .purple
        case .scrolling: return .green
        case .recording: return .red
        case .gif:       return .pink
        }
    }
}
