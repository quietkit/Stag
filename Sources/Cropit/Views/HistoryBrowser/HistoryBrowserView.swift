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
    @State private var singleTapWork: DispatchWorkItem?

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]

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
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filtered) { record in
                    thumbnailCell(record)
                        // Double-click opens the editor; single click only selects.
                        // Use a short delay so the double-tap cancels the single-tap action.
                        .onTapGesture(count: 2) {
                            singleTapWork?.cancel()
                            openEditor(record)
                        }
                        .onTapGesture(count: 1) {
                            singleTapWork?.cancel()
                            let work = DispatchWorkItem { selectedId = record.id }
                            singleTapWork = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                        }
                }
            }
            .padding(18)
        }
    }

    private func thumbnailCell(_ record: CaptureRecord) -> some View {
        let isSelected = selectedId == record.id
        let isHovered = hoveredId == record.id
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // "Cover" pattern: a fixed-height, full-width box that the image
                // fills and crops, so every aspect ratio fills the cell width.
                Color(nsColor: .controlBackgroundColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 124)
                    .overlay { thumbnailImage(record) }
                    .clipped()
                typeBadge(record.type)
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.accentColor
                            : (isHovered ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.15)),
                            lineWidth: isSelected || isHovered ? 2 : 1)
            )
            .shadow(color: .black.opacity(isHovered ? 0.18 : 0), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(1)
                Text("\(record.imageWidth) × \(record.imageHeight)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            hoveredId = hovering ? record.id : (hoveredId == record.id ? nil : hoveredId)
            // set() (not push/pop) — can't leak an unbalanced cursor stack when a
            // hovered cell is recycled out of the lazy grid mid-scroll.
            if hovering { NSCursor.pointingHand.set() }
            else if hoveredId == nil { NSCursor.arrow.set() }
        }
        .help("Double-click to open in editor")
        .contextMenu { cellContextMenu(record) }
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
        let editor = EditorWindow(image: image, filePath: record.filePath)
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
