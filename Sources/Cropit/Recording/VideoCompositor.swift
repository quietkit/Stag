import Cocoa
import CoreImage
import CoreMedia
import Accelerate

final class VideoCompositor {
    private let ciContext: CIContext = {
        let opts = [CIContextOption.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!]
        return CIContext(options: opts)
    }()

    @discardableResult
    func applyOverlays(to pixelBuffer: CVPixelBuffer,
                       timestamp: CMTime,
                       webcamFrame: CGImage?,
                       webcamPosition: WebcamPosition,
                       webcamSize: WebcamSize,
                       webcamEnabled: Bool,
                       showMouseClicks: Bool,
                       outputSize: CGSize) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        guard let ctx = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return nil
        }

        let date = Date(timeIntervalSince1970: CMTimeGetSeconds(timestamp))

        if showMouseClicks {
            MouseClickManager.shared.drawClickRipple(on: ctx, at: date)
        }

        if webcamEnabled, let webcam = webcamFrame {
            drawWebcamPiP(on: ctx, webcam: webcam,
                          position: webcamPosition,
                          size: webcamSize,
                          canvasWidth: width,
                          canvasHeight: height)
        }

        ctx.flush()
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        return pixelBuffer
    }

    private func drawWebcamPiP(on ctx: CGContext, webcam: CGImage,
                                position: WebcamPosition,
                                size: WebcamSize,
                                canvasWidth: Int,
                                canvasHeight: Int) {
        let pipSize = size.size
        var origin: CGPoint

        let margin: CGFloat = 16

        switch position {
        case .topLeft:
            origin = CGPoint(x: margin, y: CGFloat(canvasHeight) - pipSize.height - margin)
        case .topRight:
            origin = CGPoint(x: CGFloat(canvasWidth) - pipSize.width - margin,
                            y: CGFloat(canvasHeight) - pipSize.height - margin)
        case .bottomLeft:
            origin = CGPoint(x: margin, y: margin)
        case .bottomRight:
            origin = CGPoint(x: CGFloat(canvasWidth) - pipSize.width - margin, y: margin)
        }

        let pipRect = CGRect(origin: origin, size: pipSize)
        let shadowPath = CGPath(roundedRect: pipRect, cornerWidth: 8, cornerHeight: 8, transform: nil)

        ctx.setShadow(offset: .zero, blur: 8, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
        ctx.addPath(shadowPath)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        ctx.saveGState()
        ctx.addPath(shadowPath)
        ctx.clip()

        ctx.interpolationQuality = .high
        ctx.draw(webcam, in: pipRect)

        ctx.restoreGState()

        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6))
        ctx.setLineWidth(2)
        ctx.addPath(shadowPath)
        ctx.strokePath()
    }

    func createOverlayPixelBuffer(from sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return imageBuffer
    }
}
