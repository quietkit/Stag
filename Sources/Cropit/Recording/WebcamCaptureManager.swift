import AVFoundation
import Cocoa
import CoreImage
import os

final class WebcamCaptureManager: NSObject {
    static let shared = WebcamCaptureManager()

    @Published private(set) var isRunning = false

    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.ganwar.Cropit.webcam.processing")
    private let ciContext: CIContext = {
        let opts = [CIContextOption.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!]
        return CIContext(options: opts)
    }()

    private var currentFrame: CGImage?
    private let frameLock = NSLock()

    var latestFrame: CGImage? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return currentFrame
    }

    func start() {
        guard !isRunning else { return }
        // Request camera permission first (macOS requires NSCameraUsageDescription)
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else {
                os_log(.error, "Camera access denied – webcam overlay disabled")
                return
            }
            DispatchQueue.main.async { self?.setupAndRunSession() }
        }
    }

    // Separate method so we can call it after permission is granted
    private func setupAndRunSession() {
        let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.first
        guard let device = device else { return }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        guard captureSession.canAddOutput(videoDataOutput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(videoDataOutput)
        if let connection = videoDataOutput.connection(with: .video) {
            if #available(macOS 14, *) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            } else {
                if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = true }
        }
        captureSession.commitConfiguration()
        processingQueue.async { [weak self] in self?.captureSession.startRunning() }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
        isRunning = false
        frameLock.lock()
        currentFrame = nil
        frameLock.unlock()
    }
}

extension WebcamCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent,
                                                     format: .RGBA8,
                                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { return }
        frameLock.lock()
        currentFrame = cgImage
        frameLock.unlock()
    }
}
