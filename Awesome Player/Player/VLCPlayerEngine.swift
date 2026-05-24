/// VLC-based playback engine using libvlc from VLC.app.
/// Handles any container/codec VLC supports — instant playback, no remuxing.
import Cocoa

protocol VLCPlayerEngineDelegate: AnyObject {
    func vlcEngineTimeDidChange(current: Double, duration: Double)
    func vlcEngineDidFinishPlaying()
    func vlcEngineDidUpdateStatus(isPlaying: Bool)
}

class VLCPlayerEngine {
    weak var delegate: VLCPlayerEngineDelegate?

    private var instance: OpaquePointer?
    private var player: OpaquePointer?
    private var media: OpaquePointer?
    private var timeUpdateTimer: Timer?

    private(set) var isPlaying = false
    private(set) var duration: Double = 0

    /// The NSView that libvlc renders into
    let renderView = NSView()

    var currentTime: Double {
        guard let p = player else { return 0 }
        return Double(libvlc_media_player_get_time(p)) / 1000.0
    }

    var volume: Float {
        get {
            guard let p = player else { return 1.0 }
            return Float(libvlc_audio_get_volume(p)) / 100.0
        }
        set {
            guard let p = player else { return }
            libvlc_audio_set_volume(p, Int32(newValue * 100))
        }
    }

    var isMuted: Bool {
        get {
            guard let p = player else { return false }
            return libvlc_audio_get_mute(p) != 0
        }
        set {
            guard let p = player else { return }
            libvlc_audio_set_mute(p, newValue ? 1 : 0)
        }
    }

    var rate: Float {
        get {
            guard let p = player else { return 1.0 }
            return libvlc_media_player_get_rate(p)
        }
        set {
            guard let p = player else { return }
            libvlc_media_player_set_rate(p, newValue)
        }
    }

    var videoSize: NSSize? {
        guard let p = player else { return nil }
        var w: UInt32 = 0, h: UInt32 = 0
        if libvlc_video_get_size(p, 0, &w, &h) == 0, w > 0, h > 0 {
            return NSSize(width: CGFloat(w), height: CGFloat(h))
        }
        return nil
    }

    init() {
        let pluginPath = Bundle.main.bundlePath + "/Contents/plugins"

        let args: [String] = [
            "--no-video-title-show",
            "--no-stats",
            "--no-snapshot-preview",
            "--vout=macosx",
        ]

        setenv("VLC_PLUGIN_PATH", pluginPath, 1)

        // Convert Swift strings to C strings for libvlc_new
        var cStrings = args.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var optionalPtrs = cStrings.map { UnsafePointer<CChar>($0) as UnsafePointer<CChar>? }
        instance = optionalPtrs.withUnsafeMutableBufferPointer { buf in
            libvlc_new(Int32(args.count), buf.baseAddress!)
        }

        if instance == nil {
            print("[VLCEngine] Failed to create libvlc instance")
        } else {
            print("[VLCEngine] libvlc instance created")
        }
    }

    deinit { stop() }

    func open(url: URL) -> Bool {
        guard let inst = instance else { return false }

        media = libvlc_media_new_path(inst, url.path)
        guard media != nil else {
            print("[VLCEngine] Failed to create media for: \(url.path)")
            return false
        }

        player = libvlc_media_player_new_from_media(media)
        guard let p = player else { return false }

        // Point libvlc at our NSView for video rendering
        renderView.wantsLayer = true
        libvlc_media_player_set_nsobject(p, Unmanaged.passUnretained(renderView).toOpaque())

        // Parse to get duration
        libvlc_media_parse(media)
        let dur = libvlc_media_get_duration(media)
        if dur > 0 { duration = Double(dur) / 1000.0 }

        print("[VLCEngine] Opened: \(url.lastPathComponent), duration=\(duration)s")
        return true
    }

    func play() {
        guard let p = player else { return }
        libvlc_media_player_play(p)
        isPlaying = true
        startTimeUpdates()
        delegate?.vlcEngineDidUpdateStatus(isPlaying: true)
    }

    func pause() {
        guard let p = player else { return }
        libvlc_media_player_pause(p)
        isPlaying = false
        delegate?.vlcEngineDidUpdateStatus(isPlaying: false)
    }

    func seek(by seconds: Double) {
        seekTo(time: max(0, min(duration, currentTime + seconds)))
    }

    func seekTo(time: Double) {
        guard let p = player else { return }
        libvlc_media_player_set_time(p, Int64(time * 1000))
    }

    func seekToFraction(_ fraction: Double) {
        guard let p = player else { return }
        libvlc_media_player_set_position(p, Float(fraction))
    }

    func stop() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
        if let p = player {
            libvlc_media_player_stop(p)
            libvlc_media_player_release(p)
        }
        if let m = media { libvlc_media_release(m) }
        player = nil
        media = nil
        isPlaying = false
    }

    private func startTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.player else { return }
            let state = libvlc_media_player_get_state(p)
            if state == libvlc_Ended {
                self.isPlaying = false
                self.timeUpdateTimer?.invalidate()
                self.delegate?.vlcEngineDidFinishPlaying()
                self.delegate?.vlcEngineDidUpdateStatus(isPlaying: false)
                return
            }
            let time = Double(libvlc_media_player_get_time(p)) / 1000.0
            let len = Double(libvlc_media_player_get_length(p)) / 1000.0
            if len > 0 { self.duration = len }
            self.delegate?.vlcEngineTimeDidChange(current: time, duration: self.duration)
        }
    }
}
