import Cocoa
import ScreenCaptureKit
import AVFoundation
import os

// MARK: - Recording Configuration

struct RecordingConfig {
    let fps: Int
    let bitRate: Int
    let captureSystemAudio: Bool
    let captureMicrophone: Bool
    let showCursor: Bool
    let outputSize: CGSize

    static func from(preferences: Preferences, targetSize: CGSize) -> RecordingConfig {
        let quality = preferences.recordingQuality
        let bitRate: Int = {
            let pixels = Int(targetSize.width * targetSize.height)
            switch quality {
            case .low:    return pixels * 2
            case .medium: return pixels * 4
            case .high:   return pixels * 8
            }
        }()
        return RecordingConfig(
            fps: preferences.recordingFps,
            bitRate: bitRate,
            captureSystemAudio: preferences.recordSystemAudio,
            captureMicrophone: preferences.recordMicrophone,
            showCursor: preferences.showCursorInRecording,
            outputSize: targetSize
        )
    }
}

// MARK: - Screen Recorder

final class ScreenRecorder: NSObject, CaptureRecorder, ObservableObject, @unchecked Sendable {
    @Published private(set) var recorderState: RecorderState = .idle
    @Published private(set) var elapsed: TimeInterval = 0

    var stream: SCStream?
    var outputURL: URL = .init(fileURLWithPath: "/tmp")
    let processingQueue = DispatchQueue(label: "com.ganwar.Cropit.recorder.processing")

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var timer: Timer?
    private var startDate: Date?
    private let stateQueue = DispatchQueue(label: "com.ganwar.Cropit.recorder.state")

    // MARK: - Start

    @MainActor
    func startCapture(filter: SCContentFilter, config: RecordingConfig, outputURL url: URL) async throws {
        guard case .idle = recorderState else { throw CaptureError.captureFailed(reason: "Recorder already active") }
        outputURL = url

        let streamConfig = SCStreamConfiguration()
        streamConfig.width = Int(config.outputSize.width)
        streamConfig.height = Int(config.outputSize.height)
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.capturesAudio = config.captureSystemAudio
        streamConfig.showsCursor = config.showCursor
        streamConfig.queueDepth = 3

        stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)
        if config.captureSystemAudio {
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: processingQueue)
        }

        try setupAssetWriter(config: config)
        try await stream?.startCapture()

        recorderState = .recording
        startTimer()
    }

    // MARK: - Stop

    @MainActor
    func stopCapture() async -> URL? {
        guard case .recording = recorderState else { return nil }
        stopTimer()
        try? await stream?.stopCapture()

        return await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                self.assetWriter?.finishWriting {
                    let url = self.outputURL
                    self.cleanup()
                    DispatchQueue.main.async {
                        self.recorderState = .finished(url)
                        continuation.resume(returning: url)
                    }
                }
            }
        }
    }

    // MARK: - Asset Writer

    private func setupAssetWriter(config: RecordingConfig) throws {
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.outputSize.width,
            AVVideoHeightKey: config.outputSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        videoInput.map { assetWriter?.add($0) }

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000,
        ]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        audioInput.map { assetWriter?.add($0) }

        guard assetWriter?.startWriting() == true else {
            throw CaptureError.captureFailed(reason: "Could not start asset writer")
        }
        assetWriter?.startSession(atSourceTime: .zero)
    }

    // MARK: - Timer

    private func startTimer() {
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startDate else { return }
            DispatchQueue.main.async {
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func cleanup() {
        stream = nil
        assetWriter = nil
        videoInput = nil
        audioInput = nil
    }
}

// MARK: - SCStreamOutput

extension ScreenRecorder: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let input = type == .screen ? videoInput : audioInput,
              input.isReadyForMoreMediaData
        else { return }
        input.append(sampleBuffer)
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if case .recording = self.recorderState {
                self.recorderState = .finished(self.outputURL)
            }
        }
    }
}
