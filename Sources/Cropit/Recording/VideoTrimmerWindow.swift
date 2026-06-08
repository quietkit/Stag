import Cocoa
import SwiftUI
import AVFoundation

final class VideoTrimmerWindow: NSWindow {
    private let hostingView: NSHostingView<VideoTrimmerView>
    let trimmerState: VideoTrimmerView.TrimmerState

    init(videoURL: URL, onExport: @escaping (URL?) -> Void) {
        let state = VideoTrimmerView.TrimmerState(videoURL: videoURL)
        self.trimmerState = state

        let size = NSSize(width: 520, height: 400)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )

        let trimView = VideoTrimmerView(state: state, onExport: onExport)
        hostingView = NSHostingView(rootView: trimView)

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Trim Video"
        isReleasedWhenClosed = false
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Video Trimmer View

struct VideoTrimmerView: View {
    @StateObject var state: TrimmerState
    let onExport: (URL?) -> Void

    class TrimmerState: ObservableObject {
        let videoURL: URL
        @Published var startTime: Double = 0
        @Published var endTime: Double = 1
        @Published var duration: Double = 1
        @Published var isExporting = false
        @Published var exportProgress: Double = 0

        var player: AVPlayer?
        var playerItem: AVPlayerItem?
        let asset: AVAsset

        init(videoURL: URL) {
            self.videoURL = videoURL
            self.asset = AVAsset(url: videoURL)
            loadMetadata()
        }

        private func loadMetadata() {
            Task {
                let duration = try? await asset.load(.duration)
                let seconds = duration?.seconds ?? 1
                await MainActor.run {
                    self.duration = seconds
                    self.endTime = seconds
                    setupPlayer()
                }
            }
        }

        private func setupPlayer() {
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            videoPreview
            trimControls
            timeLabels
            actionButtons
        }
        .padding()
        .frame(width: 500, height: 380)
    }

    private var videoPreview: some View {
        ZStack {
            if let player = state.player {
                VideoPlayerView(player: player)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .frame(height: 200)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
    }

    private var trimControls: some View {
        VStack(spacing: 8) {
            Slider(value: $state.startTime, in: 0...(state.duration - 0.1), step: 0.1)
                .tint(.blue)

            Slider(value: $state.endTime, in: 0.1...state.duration, step: 0.1)
                .tint(.green)

            RangeSliderView(
                startTime: $state.startTime,
                endTime: $state.endTime,
                duration: state.duration
            )
            .frame(height: 30)
        }
    }

    private var timeLabels: some View {
        HStack {
            Text("Start: \(formatTime(state.startTime))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text("Duration: \(formatTime(state.endTime - state.startTime))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text("End: \(formatTime(state.endTime))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Cancel") {
                onExport(nil)
                closeWindow()
            }
            .keyboardShortcut(.escape)

            Spacer()

            if state.isExporting {
                ProgressView(value: state.exportProgress)
                    .frame(width: 120)
                Text("\(Int(state.exportProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button("Export Trimmed") {
                    exportTrimmed()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(state.startTime >= state.endTime - 0.1)
            }
        }
    }

    private func exportTrimmed() {
        state.isExporting = true
        let sourceURL = state.videoURL
        let outputURL = sourceURL.deletingPathExtension().appendingPathExtension("trimmed.mp4")

        let start = CMTime(seconds: state.startTime, preferredTimescale: 600)
        let end = CMTime(seconds: state.endTime, preferredTimescale: 600)
        let duration = CMTimeSubtract(end, start)

        guard let exportSession = AVAssetExportSession(asset: state.asset, presetName: AVAssetExportPresetHighestQuality) else {
            state.isExporting = false
            onExport(nil)
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = CMTimeRange(start: start, duration: duration)
        exportSession.exportAsynchronously { [state, sourceURL, outputURL, onExport] in
            DispatchQueue.main.async {
                state.isExporting = false
                switch exportSession.status {
                case .completed:
                    try? FileManager.default.removeItem(at: sourceURL)
                    try? FileManager.default.moveItem(at: outputURL, to: sourceURL)
                    onExport(sourceURL)
                case .cancelled, .failed:
                    try? FileManager.default.removeItem(at: outputURL)
                    onExport(nil)
                default:
                    break
                }
                self.closeWindow()
            }
        }
    }

    private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    private func formatTime(_ time: Double) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        let cs = Int((time - Double(Int(time))) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}

// MARK: - Video Player View (NSViewRepresentable)

struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.frame = view.bounds
        view.layer?.addSublayer(playerLayer)

        DispatchQueue.main.async {
            player.play()
            player.rate = 0.5
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let sublayer = nsView.layer?.sublayers?.first as? AVPlayerLayer {
            sublayer.frame = nsView.bounds
            sublayer.player = player
        }
    }
}

// MARK: - Range Slider View

struct RangeSliderView: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double

    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let startX = CGFloat(startTime / max(duration, 1)) * width
            let endX = CGFloat(endTime / max(duration, 1)) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 8)
                    .clipShape(Capsule())

                Rectangle()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: max(endX - startX, 4), height: 8)
                    .offset(x: startX)
                    .clipShape(Capsule())

                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(radius: 2)
                    .offset(x: startX - 8)
                    .gesture(DragGesture().onChanged { value in
                        let newX = min(max(value.location.x, 0), width - 4)
                        let newTime = Double(newX / width) * duration
                        startTime = min(max(newTime, 0), endTime - 0.2)
                    })

                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(radius: 2)
                    .offset(x: endX - 8)
                    .gesture(DragGesture().onChanged { value in
                        let newX = min(max(value.location.x, 4), width)
                        let newTime = Double(newX / width) * duration
                        endTime = max(min(newTime, duration), startTime + 0.2)
                    })
            }
        }
    }
}
