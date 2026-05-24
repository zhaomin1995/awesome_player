/// Direct FFmpeg playback engine. Uses wall-clock timing (not CMTimebase)
/// for frame display, matching VLC/Movist's approach.
import AVFoundation
import AudioToolbox
import CoreMedia
import QuartzCore

protocol FFmpegPlayerEngineDelegate: AnyObject {
    func ffmpegEngineTimeDidChange(current: Double, duration: Double)
    func ffmpegEngineDidFinishPlaying()
    func ffmpegEngineDidUpdateStatus(isPlaying: Bool)
}

class FFmpegPlayerEngine: NSObject, FFmpegDecoderDelegate {
    weak var delegate: FFmpegPlayerEngineDelegate?

    private let decoder = FFmpegDecoder()
    private(set) var displayLayer: AVSampleBufferDisplayLayer?

    private var audioUnit: AudioComponentInstance?
    var audioRingBuffer = Data()
    let audioLock = NSLock()

    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private var currentTime_: Double = 0
    private var lastUIUpdate: Double = 0

    private var wallClockOrigin: Double = 0
    private var ptsOrigin: Double = -1
    private var seekInProgress = false
    private var lastFrameWallTime: Double = 0
    private var lastFramePTS: Double = 0

    var videoSize: NSSize? {
        guard decoder.hasVideo else { return nil }
        return NSSize(width: CGFloat(decoder.videoWidth), height: CGFloat(decoder.videoHeight))
    }

    var currentTime: Double { currentTime_ }
    var volume: Float = 1.0
    var isMuted: Bool = false

    override init() {
        super.init()
        decoder.delegate = self
    }

    deinit { stop() }

    // MARK: - Public API

    func open(url: URL) -> Bool {
        guard decoder.openFile(url.path) else { return false }
        duration = decoder.duration

        if decoder.hasVideo {
            let layer = AVSampleBufferDisplayLayer()
            layer.videoGravity = .resizeAspectFill
            displayLayer = layer
        }
        if decoder.hasAudio {
            setupAudioUnit()
        }
        return true
    }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        ptsOrigin = -1 // re-anchor on next frame
        startAudioUnit()
        decoder.play()
        delegate?.ffmpegEngineDidUpdateStatus(isPlaying: true)
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        decoder.pause()
        stopAudioUnit()
        delegate?.ffmpegEngineDidUpdateStatus(isPlaying: false)
    }

    func seek(by seconds: Double) {
        seekTo(time: max(0, min(duration, currentTime_ + seconds)))
    }

    func seekToFraction(_ fraction: Double) {
        seekTo(time: fraction * duration)
    }

    private var seekTargetTime: Double = 0

    func seekTo(time: Double) {
        seekInProgress = true
        ptsOrigin = -1
        seekTargetTime = time
        currentTime_ = time
        displayLayer?.flush()
        audioLock.lock()
        audioRingBuffer.removeAll()
        audioLock.unlock()
        decoder.seek(to: time)
    }

    func stop() {
        isPlaying = false
        decoder.close()
        stopAudioUnit()
        destroyAudioUnit()
        displayLayer?.flush()
        displayLayer = nil
        audioLock.lock()
        audioRingBuffer.removeAll()
        audioLock.unlock()
    }

    // MARK: - FFmpegDecoderDelegate (called on decode thread)

    func decoderDidDecodeVideoFrame(_ pixelBuffer: CVPixelBuffer, pts: Double, duration frameDuration: Double) {
        if seekInProgress { return }
        // Don't let reference frames before the seek target regress currentTime
        if pts >= seekTargetTime {
            currentTime_ = pts
        }

        // Simple frame-to-frame timing: sleep for the PTS delta since last frame
        let now = CACurrentMediaTime()
        if ptsOrigin < 0 {
            // First frame after start/seek — display immediately
            ptsOrigin = pts
            lastFrameWallTime = now
            lastFramePTS = pts
        } else {
            // Calculate how long to wait based on PTS difference
            let ptsDelta = pts - lastFramePTS
            let wallDelta = now - lastFrameWallTime
            var wait = ptsDelta - wallDelta

            if wait > 0.5 { wait = 0 } // sanity cap

            while wait > 0.002 && !seekInProgress && isPlaying {
                usleep(min(5000, UInt32(wait * 1_000_000)))
                wait = (lastFrameWallTime + ptsDelta) - CACurrentMediaTime()
            }
            if seekInProgress { return }
            if wait < -0.1 { return } // drop late frame
        }

        lastFrameWallTime = CACurrentMediaTime()
        lastFramePTS = pts

        guard let layer = displayLayer else { return }

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDesc)
        guard let fmt = formatDesc else { return }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(seconds: frameDuration, preferredTimescale: 90000),
            presentationTimeStamp: CMTime(seconds: pts, preferredTimescale: 90000),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil,
            formatDescription: fmt, sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        guard let sb = sampleBuffer else { return }

        // Display immediately — timing is handled by the sleep above
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as? [NSMutableDictionary],
           let dict = attachments.first {
            dict[kCMSampleAttachmentKey_DisplayImmediately] = true
        }

        if layer.isReadyForMoreMediaData {
            layer.enqueue(sb)
        }

        // Throttled UI update
        let uiNow = CACurrentMediaTime()
        if uiNow - lastUIUpdate > 0.25 {
            lastUIUpdate = uiNow
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.ffmpegEngineTimeDidChange(current: pts, duration: self.duration)
            }
        }
    }

    func decoderDidDecodeAudioSamples(_ pcmData: Data, channels: Int32, sampleRate: Int32, pts: Double) {
        if seekInProgress { return }
        audioLock.lock()
        audioRingBuffer.append(pcmData)
        // Cap at ~1 second of audio
        let maxBytes = Int(sampleRate) * 2 * MemoryLayout<Float>.size
        if audioRingBuffer.count > maxBytes {
            audioRingBuffer.removeFirst(audioRingBuffer.count - maxBytes)
        }
        audioLock.unlock()
    }

    func decoderDidCompleteSeek() {
        seekInProgress = false
        ptsOrigin = -1
        lastFrameWallTime = 0
        lastFramePTS = 0
    }

    func decoderDidFinishPlaying() {
        isPlaying = false
        stopAudioUnit()
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.ffmpegEngineDidFinishPlaying()
            self?.delegate?.ffmpegEngineDidUpdateStatus(isPlaying: false)
        }
    }

    func decoderDidUpdateDuration(_ duration: Double) {
        self.duration = duration
    }

    // MARK: - AudioUnit

    private func setupAudioUnit() {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_DefaultOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &desc) else { return }
        guard AudioComponentInstanceNew(component, &audioUnit) == noErr else { return }

        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: Float64(decoder.audioSampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * MemoryLayout<Float>.size),
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
        )
        AudioUnitSetProperty(audioUnit!, kAudioUnitProperty_StreamFormat,
                           kAudioUnitScope_Input, 0, &streamFormat,
                           UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        var callbackStruct = AURenderCallbackStruct(
            inputProc: ffmpegAudioRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(audioUnit!, kAudioUnitProperty_SetRenderCallback,
                           kAudioUnitScope_Input, 0, &callbackStruct,
                           UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        AudioUnitInitialize(audioUnit!)
    }

    private func startAudioUnit() {
        guard let au = audioUnit else { return }
        AudioOutputUnitStart(au)
    }

    private func stopAudioUnit() {
        guard let au = audioUnit else { return }
        AudioOutputUnitStop(au)
    }

    private func destroyAudioUnit() {
        if let au = audioUnit {
            AudioOutputUnitStop(au)
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            audioUnit = nil
        }
    }
}

private func ffmpegAudioRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32, inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<FFmpegPlayerEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    guard let bufferList = ioData else { return noErr }
    let buffer = bufferList.pointee.mBuffers
    let bytesNeeded = Int(inNumberFrames) * 2 * MemoryLayout<Float>.size
    guard let outPtr = buffer.mData else { return noErr }

    engine.audioLock.lock()
    let available = engine.audioRingBuffer.count
    if available >= bytesNeeded {
        engine.audioRingBuffer.copyBytes(to: outPtr.assumingMemoryBound(to: UInt8.self), count: bytesNeeded)
        engine.audioRingBuffer.removeFirst(bytesNeeded)
    } else if available > 0 {
        engine.audioRingBuffer.copyBytes(to: outPtr.assumingMemoryBound(to: UInt8.self), count: available)
        memset(outPtr.advanced(by: available), 0, bytesNeeded - available)
        engine.audioRingBuffer.removeAll()
    } else {
        memset(outPtr, 0, bytesNeeded)
    }
    engine.audioLock.unlock()

    // Volume + mute
    let vol = engine.isMuted ? Float(0) : engine.volume
    if vol != 1.0 {
        let floatPtr = outPtr.assumingMemoryBound(to: Float.self)
        let count = bytesNeeded / MemoryLayout<Float>.size
        for i in 0..<count { floatPtr[i] *= vol }
    }
    return noErr
}
