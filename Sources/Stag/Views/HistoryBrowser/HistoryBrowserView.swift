import SwiftUI

// MARK: - Date Range Filter

private enum DateRange: String, CaseIterable {
    case all, today, week, month

    var label: String {
        switch self {
        case .all:   return "All Time"
        case .today: return "Today"
        case .week:  return "This Week"
        case .month: return "This Month"
        }
    }

    func matches(_ date: Date) -> Bool {
        let cal = Calendar.current
        switch self {
        case .all:   return true
        case .today: return cal.isDateInToday(date)
        case .week:  return cal.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        case .month: return cal.isDate(date, equalTo: Date(), toGranularity: .month)
        }
    }
}

// MARK: - View Mode

private enum ViewMode: String, CaseIterable {
    case grid, collections
}

// MARK: - Main View

struct HistoryBrowserView: View {
    @StateObject private var store = AppStore.shared.history
    @State private var filterType: CaptureType? = nil
    @State private var searchText = ""
    @State private var hoveredId: UUID?
    @State private var dateRange: DateRange = .all
    @State private var showFavoritesOnly = false
    @State private var viewMode: ViewMode = .grid

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]

    // MARK: - Filtering

    private var filtered: [CaptureRecord] {
        store.records.filter { r in
            if showFavoritesOnly && !r.isFavorite { return false }
            if let t = filterType, r.type != t { return false }
            if !dateRange.matches(r.date) { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let fn = (r.filePath as NSString).lastPathComponent.lowercased()
                let dateStr = r.date.formatted(date: .abbreviated, time: .shortened).lowercased()
                let matchesSearch = fn.contains(q)
                    || dateStr.contains(q)
                    || r.ocrText?.localizedCaseInsensitiveContains(q) == true
                    || r.appName?.localizedCaseInsensitiveContains(q) == true
                if !matchesSearch { return false }
            }
            return true
        }
    }

    // Group filtered records by app name for collections view
    private var groupedByApp: [(key: String, records: [CaptureRecord])] {
        var dict: [String: [CaptureRecord]] = [:]
        for r in filtered {
            let key = r.appName ?? "Other"
            dict[key, default: []].append(r)
        }
        return dict.map { (key: $0.key, records: $0.value) }
            .sorted { $0.key < $1.key }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filtered.isEmpty {
                emptyState
            } else if viewMode == .collections {
                collectionsView
            } else {
                thumbnailGrid(filtered)
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search by name, app, date…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                // Favorites toggle
                Button {
                    withAnimation(.spring(response: 0.2)) { showFavoritesOnly.toggle() }
                } label: {
                    Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(showFavoritesOnly ? .yellow : .secondary)
                        .frame(width: 32, height: 32)
                        .background(showFavoritesOnly ? Color.yellow.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(showFavoritesOnly ? "Show all" : "Show favorites only")

                // View mode toggle
                Button {
                    withAnimation(.spring(response: 0.2)) {
                        viewMode = viewMode == .grid ? .collections : .grid
                    }
                } label: {
                    Image(systemName: viewMode == .collections ? "square.grid.2x2" : "rectangle.3.group")
                        .font(.system(size: 14))
                        .foregroundColor(viewMode == .collections ? .accentColor : .secondary)
                        .frame(width: 32, height: 32)
                        .background(viewMode == .collections ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(viewMode == .collections ? "Grid view" : "Collections (by app)")

                Text("\(filtered.count)/\(store.records.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            filterBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Type filters
                filterChip("All", isActive: filterType == nil) {
                    withAnimation(.spring(response: 0.2)) { filterType = nil }
                }
                ForEach(CaptureType.allCases, id: \.self) { t in
                    filterChip(typeLabel(t), isActive: filterType == t) {
                        withAnimation(.spring(response: 0.2)) { filterType = t }
                    }
                }

                Divider().frame(height: 16)

                // Date range filters
                ForEach(DateRange.allCases, id: \.self) { range in
                    if range != .all {
                        filterChip(range.label, isActive: dateRange == range) {
                            withAnimation(.spring(response: 0.2)) {
                                dateRange = dateRange == range ? .all : range
                            }
                        }
                    }
                }
            }
        }
    }

    private func filterChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: showFavoritesOnly ? "star.slash" : "camera.viewfinder")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(showFavoritesOnly ? "No favorites yet" : "No captures yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            Text(showFavoritesOnly ? "Star a capture to add it to favorites." : "Take a screenshot and it will appear here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Collections View

    private var collectionsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedByApp, id: \.key) { group in
                    Section {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(group.records) { record in
                                thumbnailCell(record)
                                    .onTapGesture { openEditor(record) }
                                    .onHover { hoveredId = $0 ? record.id : nil }
                            }
                        }
                    } header: {
                        collectionHeader(group.key, count: group.records.count)
                    }
                }
            }
            .padding(18)
        }
    }

    private func collectionHeader(_ appName: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "app.dashed")
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
            Text(appName)
                .font(.system(size: 13, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Thumbnail Grid

    private func thumbnailGrid(_ records: [CaptureRecord]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(records) { record in
                    thumbnailCell(record)
                        .onTapGesture { openEditor(record) }
                        .onHover { hoveredId = $0 ? record.id : nil }
                }
            }
            .padding(18)
        }
    }

    // MARK: - Thumbnail Cell

    private func thumbnailCell(_ record: CaptureRecord) -> some View {
        let isHovered = hoveredId == record.id
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Color(nsColor: .controlBackgroundColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 124)
                    .overlay { thumbnailImage(record) }
                    .clipped()

                // Badges row (top-right)
                HStack(spacing: 4) {
                    if record.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(4)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                    typeBadge(record.type)
                }
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isHovered ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.15),
                            lineWidth: isHovered ? 2 : 1)
            )
            .shadow(color: .black.opacity(isHovered ? 0.18 : 0), radius: 6, y: 3)
            .overlay(alignment: .bottomLeading) {
                if isHovered {
                    starButton(record)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                if let app = record.appName {
                    Text(app)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                }
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
        .background(RoundedRectangle(cornerRadius: 12).fill(.clear))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .help("Click to open in editor")
        .contextMenu { cellContextMenu(record) }
    }

    private func starButton(_ record: CaptureRecord) -> some View {
        Button {
            withAnimation { store.toggleFavorite(record.id) }
        } label: {
            Image(systemName: record.isFavorite ? "star.fill" : "star")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(record.isFavorite ? .yellow : .white)
                .frame(width: 22, height: 22)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(record.isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private func thumbnailImage(_ record: CaptureRecord) -> some View {
        Group {
            if let image = NSImage(contentsOfFile: record.thumbnailPath) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if let image = NSImage(contentsOfFile: record.filePath) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay(Image(systemName: "questionmark").foregroundColor(.secondary))
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
        Button(record.isFavorite ? "Remove from Favorites" : "Add to Favorites",
               systemImage: record.isFavorite ? "star.slash" : "star") {
            store.toggleFavorite(record.id)
        }
        Divider()
        Button("Reveal in Finder", systemImage: "folder") { revealInFinder(record) }
        Button("Copy Image", systemImage: "doc.on.doc") { copyImage(record) }
        if let ocr = record.ocrText, !ocr.isEmpty {
            Button("Copy OCR Text", systemImage: "text.viewfinder") { copyOCR(record) }
        }
        Button("Export Metadata (JSON)", systemImage: "doc.badge.arrow.up") { exportMetadata(record) }
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
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.filePath)])
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

    private func exportMetadata(_ record: CaptureRecord) {
        if let url = store.exportMetadata(for: record) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Helpers

    private func typeLabel(_ type: CaptureType) -> String {
        switch type {
        case .area:       return "Area"
        case .window:     return "Window"
        case .fullscreen: return "Fullscreen"
        case .scrolling:  return "Scrolling"
        case .recording:  return "Recording"
        case .gif:        return "GIF"
        }
    }

    private func typeShortLabel(_ type: CaptureType) -> String {
        switch type {
        case .area:       return "⌗"
        case .window:     return "⊞"
        case .fullscreen: return "⬡"
        case .scrolling:  return "⇟"
        case .recording:  return "●"
        case .gif:        return "GIF"
        }
    }

    private func typeColor(_ type: CaptureType) -> Color {
        switch type {
        case .area:       return .blue
        case .window:     return .orange
        case .fullscreen: return .purple
        case .scrolling:  return .green
        case .recording:  return .red
        case .gif:        return .pink
        }
    }
}
