import SwiftUI
import UniformTypeIdentifiers

enum ThumbnailAction {
    case save, edit, discard, copy, reveal, pin
}

struct FloatingThumbnailView: View {
    let image: NSImage
    let index: Int
    let count: Int
    let onAction: (ThumbnailAction) -> Void
    let onNavigate: (Int) -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailContent
            if hovering {
                actionsOverlay
            }
            if hovering && count > 1 {
                navOverlay
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width < -50 { onNavigate(1) }
                    if value.translation.width > 50 { onNavigate(-1) }
                }
        )
        .contextMenu { contextMenu }
    }

    private var thumbnailSize: CGSize {
        count > 1 ? CGSize(width: 200, height: 130) : CGSize(width: 240, height: 160)
    }

    private var thumbnailContent: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .onDrag {
                let provider = NSItemProvider(object: image)
                provider.suggestedName = "Cropit_\(Date().shotTimestamp).png"
                return provider
            }
    }

    // MARK: - Actions

    private var actionsOverlay: some View {
        HStack(spacing: 6) {
            actionButton("square.and.arrow.down", .save, .green)
            actionButton("pencil.tip.crop.circle", .edit, .blue)
            actionButton("doc.on.clipboard", .copy, .orange)
            actionButton("xmark.circle.fill", .discard, .red)
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(6)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    private func actionButton(_ icon: String, _ action: ThumbnailAction, _ color: Color) -> some View {
        Button { onAction(action) } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.8))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private var navOverlay: some View {
        VStack {
            Spacer()
            HStack {
                navButton("chevron.left") { onNavigate(-1) }
                Spacer()
                Text("\(index + 1) of \(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
                Spacer()
                navButton("chevron.right") { onNavigate(1) }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(.black.opacity(0.4))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context Menu

    private var contextMenu: some View {
        Group {
            Button("Save") { onAction(.save) }
                .keyboardShortcut("s")
            Button("Copy to Clipboard") { onAction(.copy) }
                .keyboardShortcut("c")
            Button("Open in Editor") { onAction(.edit) }
                .keyboardShortcut("e")
            Divider()
            Button("Pin to Screen") { onAction(.pin) }
                .keyboardShortcut("p")
            Button("Reveal in Finder") { onAction(.reveal) }
                .keyboardShortcut("r")
            Divider()
            Button("Discard", role: .destructive) { onAction(.discard) }
        }
    }
}
