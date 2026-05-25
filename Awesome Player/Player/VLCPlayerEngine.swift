/// VLC-based playback engine using libvlc from VLC.app.
/// Handles any container/codec VLC supports — instant playback, no remuxing.
/// Uses libvlc event manager for time/position updates instead of polling.
import Cocoa

protocol VLCPlayerEngineDelegate: AnyObject {
    func vlcEngineTimeDidChange(current: Double, duration: Double)
    func vlcEngineDidFinishPlaying()
    func vlcEngineDidUpdateStatus(isPlaying: Bool)
}

class VLCPlayerEngine {
    weak var delegate: VLCPlayerEngineDelegate?

    private static var sharedVLCInstance: OpaquePointer? = {
        let pluginPath = Bundle.main.bundlePath + "/Contents/plugins"
        let args: [String] = ["--no-video-title-show", "--no-stats", "--no-snapshot-preview", "--vout=macosx"]
        setenv("VLC_PLUGIN_PATH", pluginPath, 1)
        var cStrings = args.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var ptrs = cStrings.map { UnsafePointer<CChar>($0) as UnsafePointer<CChar>? }
        let inst = ptrs.withUnsafeMutableBufferPointer { buf in
            libvlc_new(Int32(args.count), buf.baseAddress!)
        }
        if inst != nil { print("[VLCEngine] Shared libvlc instance created") }
        return inst
    }()

    private var instance: OpaquePointer?
    private var player: OpaquePointer?
    private var media: OpaquePointer?
    private var eventManager: OpaquePointer?

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

    private var equalizer: OpaquePointer?

    var videoSize: NSSize? {
        guard let p = player else { return nil }
        var w: UInt32 = 0, h: UInt32 = 0
        if libvlc_video_get_size(p, 0, &w, &h) == 0, w > 0, h > 0 {
            return NSSize(width: CGFloat(w), height: CGFloat(h))
        }
        return nil
    }

    init() {
        instance = Self.sharedVLCInstance
        if instance == nil {
            print("[VLCEngine] Failed to get libvlc instance")
        }
    }

    deinit {
        stop()
    }

    func open(url: URL) -> Bool {
        guard let inst = instance else { return false }

        media = libvlc_media_new_path(inst, url.path)
        guard media != nil else {
            print("[VLCEngine] Failed to create media for: \(url.path)")
            return false
        }

        // Apply audio normalization if enabled
        if let m = media {
            if UserDefaults.standard.bool(forKey: Defaults.normalizationEnabled) {
                libvlc_media_add_option(m, "--audio-filter=normvol")
            }
            if UserDefaults.standard.bool(forKey: Defaults.compressorEnabled) {
                libvlc_media_add_option(m, "--audio-filter=compressor")
            }
        }

        player = libvlc_media_player_new_from_media(media)
        guard let p = player else { return false }

        renderView.wantsLayer = true
        libvlc_media_player_set_nsobject(p, Unmanaged.passUnretained(renderView).toOpaque())

        duration = 0
        attachEvents()

        print("[VLCEngine] Opened: \(url.lastPathComponent)")
        return true
    }

    func play() {
        guard let p = player else { return }
        libvlc_media_player_play(p)
        isPlaying = true
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
        detachEvents()
        if let eq = equalizer {
            libvlc_audio_equalizer_release(eq)
            equalizer = nil
        }
        if let p = player {
            libvlc_media_player_stop(p)
            libvlc_media_player_release(p)
        }
        if let m = media { libvlc_media_release(m) }
        player = nil
        media = nil
        eventManager = nil
        isPlaying = false
    }

    // MARK: - Frame Stepping

    func stepFrame() {
        guard let p = player else { return }
        if isPlaying { pause() }
        libvlc_media_player_next_frame(p)
    }

    // MARK: - Event-Driven Updates

    private func attachEvents() {
        guard let p = player else { return }
        eventManager = libvlc_media_player_event_manager(p)
        guard let em = eventManager else { return }

        let ctx = Unmanaged.passUnretained(self).toOpaque()

        libvlc_event_attach(em, Int32(libvlc_MediaPlayerTimeChanged), vlcTimeChanged, ctx)
        libvlc_event_attach(em, Int32(libvlc_MediaPlayerLengthChanged), vlcLengthChanged, ctx)
        libvlc_event_attach(em, Int32(libvlc_MediaPlayerEndReached), vlcEndReached, ctx)
        libvlc_event_attach(em, Int32(libvlc_MediaPlayerPlaying), vlcPlaying, ctx)
        libvlc_event_attach(em, Int32(libvlc_MediaPlayerPaused), vlcPaused, ctx)
        libvlc_event_attach(em, Int32(libvlc_MediaPlayerStopped), vlcStopped, ctx)
    }

    private func detachEvents() {
        guard let em = eventManager else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        libvlc_event_detach(em, Int32(libvlc_MediaPlayerTimeChanged), vlcTimeChanged, ctx)
        libvlc_event_detach(em, Int32(libvlc_MediaPlayerLengthChanged), vlcLengthChanged, ctx)
        libvlc_event_detach(em, Int32(libvlc_MediaPlayerEndReached), vlcEndReached, ctx)
        libvlc_event_detach(em, Int32(libvlc_MediaPlayerPlaying), vlcPlaying, ctx)
        libvlc_event_detach(em, Int32(libvlc_MediaPlayerPaused), vlcPaused, ctx)
        libvlc_event_detach(em, Int32(libvlc_MediaPlayerStopped), vlcStopped, ctx)
    }

    fileprivate func handleTimeChanged(_ timeMs: Int64) {
        let time = Double(timeMs) / 1000.0
        guard let p = player else { return }
        let len = Double(libvlc_media_player_get_length(p)) / 1000.0
        if len > 0 { duration = len }
        delegate?.vlcEngineTimeDidChange(current: time, duration: duration)
    }

    fileprivate func handleLengthChanged(_ lengthMs: Int64) {
        let len = Double(lengthMs) / 1000.0
        if len > 0 { duration = len }
    }

    fileprivate func handleEndReached() {
        isPlaying = false
        delegate?.vlcEngineDidFinishPlaying()
        delegate?.vlcEngineDidUpdateStatus(isPlaying: false)
    }

    fileprivate func handlePlaying() {
        isPlaying = true
        delegate?.vlcEngineDidUpdateStatus(isPlaying: true)
    }

    fileprivate func handlePaused() {
        isPlaying = false
        delegate?.vlcEngineDidUpdateStatus(isPlaying: false)
    }

    fileprivate func handleStopped() {
        isPlaying = false
        delegate?.vlcEngineDidUpdateStatus(isPlaying: false)
    }

    // MARK: - Track Switching

    struct TrackInfo {
        let id: Int
        let name: String
    }

    func getAudioTracks() -> [TrackInfo] {
        guard let p = player else { return [] }
        return parseTrackDescriptions(libvlc_audio_get_track_description(p))
    }

    func getSubtitleTracks() -> [TrackInfo] {
        guard let p = player else { return [] }
        return parseTrackDescriptions(libvlc_video_get_spu_description(p))
    }

    func getVideoTracks() -> [TrackInfo] {
        guard let p = player else { return [] }
        return parseTrackDescriptions(libvlc_video_get_track_description(p))
    }

    func getCurrentAudioTrack() -> Int {
        guard let p = player else { return -1 }
        return Int(libvlc_audio_get_track(p))
    }

    func getCurrentSubtitleTrack() -> Int {
        guard let p = player else { return -1 }
        return Int(libvlc_video_get_spu(p))
    }

    func setAudioTrack(_ trackId: Int) {
        guard let p = player else { return }
        libvlc_audio_set_track(p, Int32(trackId))
    }

    func setSubtitleTrack(_ trackId: Int) {
        guard let p = player else { return }
        libvlc_video_set_spu(p, Int32(trackId))
    }

    func setVideoTrack(_ trackId: Int) {
        guard let p = player else { return }
        libvlc_video_set_track(p, Int32(trackId))
    }

    func addSubtitleFile(_ path: String) {
        guard let p = player else { return }
        let uri = URL(fileURLWithPath: path).absoluteString
        libvlc_media_player_add_slave(p, libvlc_media_slave_type_subtitle, uri, 1)
    }

    private func parseTrackDescriptions(_ head: UnsafeMutablePointer<libvlc_track_description_t>?) -> [TrackInfo] {
        var tracks: [TrackInfo] = []
        var current = head
        while let desc = current {
            let name: String
            if let psz = desc.pointee.psz_name {
                name = String(cString: psz)
            } else {
                name = "Track \(desc.pointee.i_id)"
            }
            tracks.append(TrackInfo(id: Int(desc.pointee.i_id), name: name))
            current = desc.pointee.p_next
        }
        if let head = head {
            libvlc_track_description_list_release(head)
        }
        return tracks
    }

    // MARK: - Equalizer

    func setEqualizer(presetIndex: Int) {
        guard let p = player else { return }
        if let eq = equalizer { libvlc_audio_equalizer_release(eq) }
        equalizer = libvlc_audio_equalizer_new_from_preset(UInt32(presetIndex))
        if let eq = equalizer {
            libvlc_media_player_set_equalizer(p, eq)
        }
    }

    func disableEqualizer() {
        guard let p = player else { return }
        libvlc_media_player_set_equalizer(p, nil)
        if let eq = equalizer {
            libvlc_audio_equalizer_release(eq)
            equalizer = nil
        }
    }

    // MARK: - Audio Delay

    func setAudioDelay(seconds: Double) {
        guard let p = player else { return }
        libvlc_audio_set_delay(p, Int64(seconds * 1_000_000))
    }

    func getAudioDelay() -> Double {
        guard let p = player else { return 0 }
        return Double(libvlc_audio_get_delay(p)) / 1_000_000
    }

    // MARK: - Snapshot

    func takeSnapshot(path: String, width: UInt32 = 0, height: UInt32 = 0) -> Bool {
        guard let p = player else { return false }
        return libvlc_video_take_snapshot(p, 0, path, width, height) == 0
    }

    // MARK: - Video Adjustments

    func setVideoAdjust(enabled: Bool) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), enabled ? 1 : 0)
    }

    func setBrightness(_ value: Float) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), 1)
        libvlc_video_set_adjust_float(p, UInt32(libvlc_adjust_Brightness), value)
    }

    func setContrast(_ value: Float) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), 1)
        libvlc_video_set_adjust_float(p, UInt32(libvlc_adjust_Contrast), value)
    }

    func setSaturation(_ value: Float) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), 1)
        libvlc_video_set_adjust_float(p, UInt32(libvlc_adjust_Saturation), value)
    }

    func setHue(_ value: Float) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), 1)
        libvlc_video_set_adjust_float(p, UInt32(libvlc_adjust_Hue), value)
    }

    func setGamma(_ value: Float) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), 1)
        libvlc_video_set_adjust_float(p, UInt32(libvlc_adjust_Gamma), value)
    }

    // MARK: - Deinterlace

    func setDeinterlace(mode: String?) {
        guard let p = player else { return }
        if let mode = mode {
            libvlc_video_set_deinterlace(p, mode)
        } else {
            libvlc_video_set_deinterlace(p, nil)
        }
    }

    // MARK: - Crop

    func setCropGeometry(_ geometry: String?) {
        guard let p = player else { return }
        if let g = geometry {
            libvlc_video_set_crop_geometry(p, g)
        } else {
            libvlc_video_set_crop_geometry(p, nil)
        }
    }

    // MARK: - Chapters

    func getChapterCount() -> Int {
        guard let p = player else { return 0 }
        return Int(libvlc_media_player_get_chapter_count(p))
    }

    func getCurrentChapter() -> Int {
        guard let p = player else { return -1 }
        return Int(libvlc_media_player_get_chapter(p))
    }

    func setChapter(_ index: Int) {
        guard let p = player else { return }
        libvlc_media_player_set_chapter(p, Int32(index))
    }
}

// MARK: - C Callbacks (must be free functions, not closures)

private func vlcTimeChanged(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let event = event, let userData = userData else { return }
    let timeMs = event.pointee.u.media_player_time_changed.new_time
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleTimeChanged(timeMs) }
}

private func vlcLengthChanged(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let event = event, let userData = userData else { return }
    let lengthMs = event.pointee.u.media_player_length_changed.new_length
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleLengthChanged(lengthMs) }
}

private func vlcEndReached(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleEndReached() }
}

private func vlcPlaying(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handlePlaying() }
}

private func vlcPaused(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handlePaused() }
}

private func vlcStopped(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleStopped() }
}
