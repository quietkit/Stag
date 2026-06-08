import AVFoundation
import Accelerate

final class AudioMixer {
    private let format: AVAudioFormat
    private let mixerBuffer: AVAudioPCMBuffer

    init?(sampleRate: Double = 44100, channels: UInt32 = 2) {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: sampleRate,
                                channels: channels,
                                interleaved: false)
        guard let format = fmt else { return nil }
        self.format = format
        let capacity = AVAudioFrameCount(sampleRate * 0.1)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        self.mixerBuffer = buffer
    }

    func mix(systemAudio: CMSampleBuffer, micAudio: CMSampleBuffer) -> CMSampleBuffer? {
        guard let systemPCM = convertToPCM(systemAudio),
              let micPCM = convertToPCM(micAudio) else {
            return systemAudio
        }

        let frameCount = min(systemPCM.frameLength, micPCM.frameLength, mixerBuffer.frameCapacity)
        mixerBuffer.frameLength = frameCount

        guard let sysData = systemPCM.floatChannelData,
              let micData = micPCM.floatChannelData,
              let mixData = mixerBuffer.floatChannelData else {
            return systemAudio
        }

        let channelCount = Int(format.channelCount)
        for ch in 0..<channelCount {
            let sysPtr = sysData[ch]
            let micPtr = micData[ch]
            let mixPtr = mixData[ch]
            let len = Int(frameCount)

            for i in 0..<len {
                let s = sysPtr[i]
                let m = micPtr[i]
                mixPtr[i] = s + m
            }

            var peak: Float = 0
            vDSP_maxmgv(mixPtr, 1, &peak, vDSP_Length(len))
            if peak > 1.0 {
                var scale: Float = 1.0 / peak
                vDSP_vsmul(mixPtr, 1, &scale, mixPtr, 1, vDSP_Length(len))
            }
        }

        return convertToSampleBuffer(mixerBuffer)
    }

    private func convertToPCM(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }

        let sampleRate = asbd.pointee.mSampleRate
        let channels = asbd.pointee.mChannelsPerFrame
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
        guard let fmt = audioFormat else { return nil }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                           totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let data = dataPointer else { return nil }

        let bytesPerFrame = Int(fmt.streamDescription.pointee.mBytesPerFrame)
        let frameLength = bytesPerFrame > 0 ? AVAudioFrameCount(length / bytesPerFrame) : 0
        guard frameLength > 0 else { return nil }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameLength) else { return nil }
        pcmBuffer.frameLength = frameLength

        memcpy(pcmBuffer.floatChannelData?[0], data, length)
        return pcmBuffer
    }

    private func convertToSampleBuffer(_ pcmBuffer: AVAudioPCMBuffer) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: format.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: format.channelCount,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var formatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       asbd: &asbd,
                                       layoutSize: 0,
                                       layout: nil,
                                       magicCookieSize: 0,
                                       magicCookie: nil,
                                       extensions: nil,
                                       formatDescriptionOut: &formatDesc)
        guard let fd = formatDesc else { return nil }

        let numSamples = pcmBuffer.frameLength
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let dataSize = Int(numSamples) * bytesPerFrame

        guard let data = pcmBuffer.floatChannelData?[0] else { return nil }
        let dataPtr = UnsafeMutableRawPointer(mutating: UnsafeRawPointer(data))

        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: dataPtr,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorNull,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let bb = blockBuffer else { return nil }

        var sampleTiming = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(format.sampleRate)),
            presentationTimeStamp: CMTime(value: 0, timescale: Int32(format.sampleRate)),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fd,
            sampleCount: CMItemCount(numSamples),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &sampleTiming,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}
