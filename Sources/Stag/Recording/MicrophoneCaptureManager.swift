import AVFoundation
import Cocoa
import os

final class MicrophoneCaptureManager: NSObject {
    static let shared = MicrophoneCaptureManager()

    private let captureSession = AVCaptureSession()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let processingQueue = DispatchQueue(label: "com.ganwar.Stag.mic.processing")
    private let logger = Logger(subsystem: "com.ganwar.Stag", category: "MicCapture")

    private var audioSampleHandler: ((CMSampleBuffer) -> Void)?
    private let handlerLock = NSLock()

    var onAudioSample: ((CMSampleBuffer) -> Void)? {
        get {
            handlerLock.lock()
            defer { handlerLock.unlock() }
            return audioSampleHandler
        }
        set {
            handlerLock.lock()
            audioSampleHandler = newValue
            handlerLock.unlock()
        }
    }

    @Published private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }

        // Request microphone access before touching the session.
        // The system shows the permission dialog on first call; subsequent calls
        // return the cached decision without a dialog.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard granted else {
                    self?.logger.warning("Microphone access denied by user")
                    return
                }
                DispatchQueue.main.async { self?.startSession() }
            }
        default:
            logger.warning("Microphone access not available — skipping mic capture")
        }
    }

    private func startSession() {
        guard !isRunning else { return }
        let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [AVCaptureDevice.DeviceType.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices.first
        guard let device = device else {
            logger.warning("No built-in microphone found")
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            logger.error("Could not create microphone input")
            return
        }

        captureSession.beginConfiguration()

        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            logger.error("Could not add microphone input to session")
            return
        }
        captureSession.addInput(input)

        audioDataOutput.setSampleBufferDelegate(self, queue: processingQueue)
        guard captureSession.canAddOutput(audioDataOutput) else {
            captureSession.commitConfiguration()
            logger.error("Could not add audio output")
            return
        }
        captureSession.addOutput(audioDataOutput)

        captureSession.commitConfiguration()

        processingQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }

        isRunning = true
        logger.notice("Microphone capture started")
    }  // end of startSession

    func stop() {
        guard isRunning else { return }
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
        isRunning = false
        onAudioSample = nil
        logger.notice("Microphone capture stopped")
    }
}

extension MicrophoneCaptureManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let handler = onAudioSample else { return }
        handler(sampleBuffer)
    }
}
