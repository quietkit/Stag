import Cocoa
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

final class GIFRecorder: NSObject, CaptureRecorder, ObservableObject, @unchecked Sendable {
    @Published private(set) var recorderState: RecorderState = .idle
    @Published private(set) var frameCount: Int = 0

    var stream: SCStream?
    var outputURL: URL = .init(fileURLWithPath: "/tmp")
    let processingQueue = DispatchQueue(label: "com.ganwar.Cropit.gifrecorder.processing", qos: .userInitiated)
    private let encodeQueue = DispatchQueue(label: "com.ganwar.Cropit.gifrecorder.encode", qos: .utility)

    private let ciContext: CIContext = {
        let opts = [CIContextOption.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!]
        return CIContext(options: opts)
    }()
    private var fps: Int = 10

    private let maxFrames = 450
    private let maxDimension: CGFloat = 800
    private var tempDir: URL!
    private var frameIndex: Int = 0
    private let frameLock = NSLock()

    @MainActor
    func startCapture(filter: SCContentFilter, config: RecordingConfig, outputURL url: URL) async throws {
        guard case .idle = recorderState else { throw CaptureError.captureFailed(reason: "GIF recorder already active") }
        outputURL = url
        fps = max(1, min(config.fps, 50))
        frameIndex = 0

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cropit_gif_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // sourceRect is in logical points; width/height must be in physical pixels.
        // Use the backing scale factor of the main (or matching) display.
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelW = max(1, Int(config.outputSize.width  * scale))
        let pixelH = max(1, Int(config.outputSize.height * scale))

        let streamConfig = SCStreamConfiguration()
        streamConfig.width  = pixelW
        streamConfig.height = pixelH
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.showsCursor = config.showCursor
        streamConfig.queueDepth = 3
        if let rect = config.captureRect {
            streamConfig.sourceRect = rect
        }

        stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)
        try await stream?.startCapture()

        recorderState = .recording
    }

    func stopCapture() async -> URL? {
        guard case .recording = recorderState else { return nil }
        try? await stream?.stopCapture()
        return await withCheckedContinuation { continuation in
            encodeQueue.async { [weak self] in
                guard let self = self else { return }
                self.encodeGIF()
                let url = self.outputURL
                self.cleanup()
                DispatchQueue.main.async {
                    self.recorderState = .finished(url)
                    continuation.resume(returning: url)
                }
            }
        }
    }

    private func encodeGIF() {
        let frameDelay = max(0.02, round(1.0 / Double(fps) * 100) / 100)
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ]

        frameLock.lock()
        let count = frameIndex
        frameLock.unlock()

        guard count > 0 else { return }
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            count,
            nil
        ) else { return }

        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        for i in 0..<count {
            let frameURL = tempDir.appendingPathComponent(String(format: "frame_%04d.png", i))
            guard let data = try? Data(contentsOf: frameURL),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { continue }
            let dithered = applyFloydSteinberg(image)
            CGImageDestinationAddImage(destination, dithered, frameProperties as CFDictionary)
        }

        CGImageDestinationFinalize(destination)

        // ImageIO always writes "GIF87a" header even for animated GIFs with extension blocks.
        // macOS Quick Look / Preview and many viewers refuse to animate GIF87a files.
        // Patch bytes 4-5 in-place: "87" → "89" to produce a proper GIF89a header.
        if let handle = try? FileHandle(forWritingTo: outputURL) {
            handle.seek(toFileOffset: 4)
            handle.write(Data([0x39]))  // '9' — turns "GIF87a" → "GIF89a"
            try? handle.close()
        }
    }

    private func applyFloydSteinberg(_ image: CGImage) -> CGImage {
        let w = image.width
        let h = image.height

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGImageByteOrderInfo.order32Big.rawValue
        )
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ),
            let data = ctx.data
        else { return image }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        for y in 0..<h {
            for x in 0..<w {
                let offset = (y * w + x) * 4

                let oldR = pixels[offset + 1]
                let oldG = pixels[offset + 2]
                let oldB = pixels[offset + 3]

                let newR = quantize6(oldR)
                let newG = quantize6(oldG)
                let newB = quantize6(oldB)

                pixels[offset + 1] = newR
                pixels[offset + 2] = newG
                pixels[offset + 3] = newB

                let errR = Int(oldR) - Int(newR)
                let errG = Int(oldG) - Int(newG)
                let errB = Int(oldB) - Int(newB)

                distribute(pixels, w: w, h: h, x: x + 1, y: y, dr: errR * 7 / 16, dg: errG * 7 / 16, db: errB * 7 / 16)
                distribute(pixels, w: w, h: h, x: x - 1, y: y + 1, dr: errR * 3 / 16, dg: errG * 3 / 16, db: errB * 3 / 16)
                distribute(pixels, w: w, h: h, x: x, y: y + 1, dr: errR * 5 / 16, dg: errG * 5 / 16, db: errB * 5 / 16)
                distribute(pixels, w: w, h: h, x: x + 1, y: y + 1, dr: errR * 1 / 16, dg: errG * 1 / 16, db: errB * 1 / 16)
            }
        }

        return ctx.makeImage() ?? image
    }

    private func quantize6(_ value: UInt8) -> UInt8 {
        let v = Int(value)
        return UInt8((v + 25) / 51 * 51)
    }

    private func distribute(_ pixels: UnsafeMutablePointer<UInt8>, w: Int, h: Int, x: Int, y: Int, dr: Int, dg: Int, db: Int) {
        guard x >= 0, x < w, y >= 0, y < h else { return }
        let offset = (y * w + x) * 4
        pixels[offset + 1] = clamp(pixels[offset + 1], dr)
        pixels[offset + 2] = clamp(pixels[offset + 2], dg)
        pixels[offset + 3] = clamp(pixels[offset + 3], db)
    }

    private func clamp(_ value: UInt8, _ delta: Int) -> UInt8 {
        let result = Int(value) + delta
        return UInt8(min(255, max(0, result)))
    }

    private func resizeIfNeeded(_ image: CGImage) -> CGImage {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        guard max(w, h) > maxDimension else { return image }
        let scale = maxDimension / max(w, h)
        let newW = Int(w * scale)
        let newH = Int(h * scale)
        let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: newW * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo
        ) else { return image }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: newW, height: newH))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }

    func cleanup() {
        stream = nil
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        frameIndex = 0
    }
}

// MARK: - SCStreamOutput

extension GIFRecorder: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { return }

        let resized = resizeIfNeeded(cgImage)

        frameLock.lock()
        let idx = frameIndex
        guard idx < maxFrames else { frameLock.unlock(); return }
        frameIndex += 1
        let count = frameIndex
        frameLock.unlock()

        let frameURL = tempDir.appendingPathComponent(String(format: "frame_%04d.png", idx))
        if let dest = CGImageDestinationCreateWithURL(frameURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, resized, nil)
            CGImageDestinationFinalize(dest)
        }

        if idx == 0 || idx % 5 == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.frameCount = count
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension GIFRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if case .recording = self.recorderState {
                self.recorderState = .finished(self.outputURL)
            }
        }
    }
}
