import AVFoundation
import Cocoa

class PlayerEngine {
    private var avPlayerEngine: AVPlayerEngine?
    private var mediaInfo: MediaInfo?

    var currentEngine: AVPlayerEngine? { avPlayerEngine }
    var isUsingAVPlayer: Bool { avPlayerEngine != nil }

    func open(url: URL, videoView: VideoView, delegate: AVPlayerEngineDelegate) async -> MediaInfo? {
        let info = await MediaInfo.probe(url: url)
        mediaInfo = info

        if info.isAVPlayerCompatible {
            return openWithAVPlayer(url: url, videoView: videoView, delegate: delegate, info: info)
        }

        // TODO: Phase 6 — FFmpeg decoder fallback for non-AVPlayer codecs
        // For now, try AVPlayer anyway
        return openWithAVPlayer(url: url, videoView: videoView, delegate: delegate, info: info)
    }

    private func openWithAVPlayer(url: URL, videoView: VideoView, delegate: AVPlayerEngineDelegate, info: MediaInfo) -> MediaInfo {
        let engine = AVPlayerEngine()
        engine.delegate = delegate
        avPlayerEngine = engine

        // TODO: Phase 5 — For MKV/AVI with AVPlayer-compatible codecs, remux first
        engine.open(url: url)
        videoView.setPlayer(engine.player)

        if info.isDolbyVision || info.hdrType != .sdr {
            configureHDR(videoView: videoView)
        }

        return info
    }

    private func configureHDR(videoView: VideoView) {
        // Enable EDR on the player layer
        // AVPlayerLayer.wantsExtendedDynamicRangeContent is set in VideoView.setPlayer()
    }

    func play() {
        avPlayerEngine?.play()
    }

    func pause() {
        avPlayerEngine?.pause()
    }

    func togglePlayPause() {
        if avPlayerEngine?.isPlaying == true {
            avPlayerEngine?.pause()
        } else {
            avPlayerEngine?.play()
        }
    }

    func seek(by seconds: Double) {
        avPlayerEngine?.seek(by: seconds)
    }

    func seekToFraction(_ fraction: Double) {
        avPlayerEngine?.seekToFraction(fraction)
    }

    var isPlaying: Bool {
        avPlayerEngine?.isPlaying ?? false
    }

    var volume: Float {
        get { avPlayerEngine?.volume ?? 1.0 }
        set { avPlayerEngine?.volume = newValue }
    }

    var isMuted: Bool {
        get { avPlayerEngine?.isMuted ?? false }
        set { avPlayerEngine?.isMuted = newValue }
    }

    var rate: Float {
        get { avPlayerEngine?.rate ?? 1.0 }
        set { avPlayerEngine?.rate = newValue }
    }

    var duration: Double {
        avPlayerEngine?.duration ?? 0
    }

    var videoSize: NSSize? {
        avPlayerEngine?.videoSize
    }

    var player: AVPlayer? {
        avPlayerEngine?.player
    }

    func stop() {
        avPlayerEngine?.stop()
        avPlayerEngine = nil
        mediaInfo = nil
    }
}
