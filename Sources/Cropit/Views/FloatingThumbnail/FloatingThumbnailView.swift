import SwiftUI
import UniformTypeIdentifiers

enum ThumbnailAction {
    case save, edit, discard, copy, reveal, pin, retake
}

struct FloatingThumbnailView: View {
    let image: NSImage
    let index: Int
    let count: Int
    let onAction: (ThumbnailAction) -> Void
    let onNavigate: (Int) -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            thumbnailContent
                .overlay(alignment: .topTrailing) {
                    if hovering { closeButton.transition(.scale.combined(with: .opacity)) }
                }
                .overlay(alignment: .bottom) {
                    if hovering { actionBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
                }
                .overlay(alignment: .top) {
                    if hovering && count > 1 {
                        navBar.transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hovering)
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
        count > 1 ? CGSize(width: 220, height: 145) : CGSize(width: 260, height: 175)
    }

    private var thumbnailContent: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
            // Single tap → open editor (primary action)
            .onTapGesture { onAction(.edit) }
            .onDrag {
                let provider = NSItemProvider(object: image)
                provider.suggestedName = "Cropit_\(Date().shotTimestamp).png"
                return provider
            }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 2) {
            actionItem("square.and.arrow.down", "Save", .save, .green)
            actionItem("pencil.tip.crop.circle", "Edit", .edit, .blue)
            actionItem("doc.on.clipboard", "Copy", .copy, .orange)
            actionItem("pin", "Pin", .pin, .purple)
            actionItem("arrow.counterclockwise.circle", "Retake", .retake, .indigo)
            actionItem("folder", "Reveal", .reveal, .secondary)
            actionItem("xmark.circle.fill", "Discard", .discard, .red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        .padding(.bottom, 8)
    }

    private func actionItem(_ icon: String, _ label: String, _ action: ThumbnailAction, _ color: Color) -> some View {
        Button { onAction(action) } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 7, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0)
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button { onAction(.discard) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
    }

    // MARK: - Navigation

    private var navBar: some View {
        HStack {
            navButton("chevron.left") { onNavigate(-1) }
            Spacer()
            Text("\(index + 1) / \(count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.45))
                .clipShape(Capsule())
            Spacer()
            navButton("chevron.right") { onNavigate(1) }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(.black.opacity(0.35))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context Menu

    private var contextMenu: some View {
        Group {
            Button("Save") { onAction(.save) }.keyboardShortcut("s")
            Button("Copy to Clipboard") { onAction(.copy) }.keyboardShortcut("c")
            Button("Open in Editor") { onAction(.edit) }.keyboardShortcut("e")
            Divider()
            Button("Pin to Screen") { onAction(.pin) }.keyboardShortcut("p")
            Button("Reveal in Finder") { onAction(.reveal) }.keyboardShortcut("r")
            Button("Retake") { onAction(.retake) }.keyboardShortcut("t")
            Divider()
            Button("Discard", role: .destructive) { onAction(.discard) }
        }
    }
}
