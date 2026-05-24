/// Main playback view controller. Handles two code paths for opening files:
/// - Native formats (MP4/MOV with H.264/HEVC) go directly to AVPlayer
/// - Non-native formats (MKV, AVI, etc.) are remuxed to a temp MP4 via FFmpeg first
///
/// The remux path keeps all playback through AVPlayer, which preserves Dolby Vision
/// and AirPlay support. A direct FFmpeg software decoder engine is planned but not yet wired up.
import Cocoa
import AVFoundation
import AVKit

class PlayerViewController: NSViewController {
    private let videoView = VideoView()
    private let welcomeView = WelcomeView()
    private let controlBarView = ControlBarView()
    private let subtitleOverlayView = SubtitleOverlayView()
    private let osdView = OSDView()
    private var controlBarBottomConstraint: NSLayoutConstraint?

    var onMouseMoved: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onFileDropped: ((URL) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?

    private var player: AVPlayer?
    private(set) var playerEngine: AVPlayerEngine?
    private var vlcEngine: VLCPlayerEngine?
    private var timeObserver: Any?

    private let subtitleManager = SubtitleManager()
    private let playlistManager = PlaylistManager()
    private let abLoopController = ABLoopController()
    private(set) var currentFileURL: URL?
    private var videoRotation: CGFloat = 0
    private var videoFlippedH = false
    private var videoFlippedV = false
    private var isFillScreen = false
    private var pipController: AVPictureInPictureController?
    private var audioDelayOffset: Double = 0
    private let passthroughManager = AudioPassthroughManager()

    var isPaused: Bool {
        player?.rate == 0
    }

    // MARK: - Preference Readers

    private var shortSeek: Double {
        let v = UserDefaults.standard.double(forKey: Defaults.shortSeekInterval)
        return v >= 1 ? v : 5
    }
    private var longSeek: Double {
        let v = UserDefaults.standard.double(forKey: Defaults.longSeekInterval)
        return v >= 1 ? v : 30
    }
    private var useKeyframeSeeking: Bool {
        UserDefaults.standard.bool(forKey: Defaults.keyFrameSeeking)
    }
    private var scrollAction: Int {
        UserDefaults.standard.integer(forKey: Defaults.scrollWheelAction)
    }

    override func loadView() {
        let dragDropView = DragDropView()
        dragDropView.wantsLayer = true
        dragDropView.layer?.backgroundColor = NSColor.black.cgColor
        dragDropView.onFileDropped = { [weak self] url in
            self?.onFileDropped?(url)
        }
        dragDropView.onArrowKey = { [weak self] key in
            guard let self = self else { return }
            switch UInt(key) {
            case UInt(NSLeftArrowFunctionKey):  self.seek(by: -self.shortSeek)
            case UInt(NSRightArrowFunctionKey): self.seek(by: self.shortSeek)
            case UInt(NSUpArrowFunctionKey):    self.adjustVolume(by: 0.05)
            case UInt(NSDownArrowFunctionKey):  self.adjustVolume(by: -0.05)
            default: break
            }
        }
        view = dragDropView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupVideoView()
        setupWelcomeView()
        setupSubtitleOverlay()
        setupControlBar()
        setupOSD()
        setupGestureRecognizers()
        registerForDraggedTypes()
        abLoopController.delegate = self
        passthroughManager.delegate = self
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExited?()
    }

    private func setupVideoView() {
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupWelcomeView() {
        welcomeView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(welcomeView)
        NSLayoutConstraint.activate([
            welcomeView.topAnchor.constraint(equalTo: view.topAnchor),
            welcomeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            welcomeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            welcomeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupSubtitleOverlay() {
        subtitleOverlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleOverlayView)
        NSLayoutConstraint.activate([
            subtitleOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            subtitleOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            subtitleOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -60),
            subtitleOverlayView.heightAnchor.constraint(lessThanOrEqualToConstant: 120),
        ])
    }

    private func setupControlBar() {
        controlBarView.translatesAutoresizingMaskIntoConstraints = false
        controlBarView.delegate = self
        view.addSubview(controlBarView)

        let bottomConstraint = controlBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        controlBarBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            bottomConstraint,
            controlBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlBarView.heightAnchor.constraint(equalToConstant: 80),
        ])
    }

    private func setupOSD() {
        osdView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(osdView)
        NSLayoutConstraint.activate([
            osdView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            osdView.topAnchor.constraint(equalTo: view.topAnchor, constant: 50),
        ])
    }

    private func setupGestureRecognizers() {
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        view.addGestureRecognizer(doubleClick)
    }

    private func registerForDraggedTypes() {
        // Drag and drop handled by DragDropView (the root view)
    }

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        onDoubleClick?()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?()
    }

    /// Scroll-wheel adjusts volume in fixed steps (not proportional to delta)
    /// to avoid accidental large jumps from trackpad momentum scrolling.
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.5 else { return }
        switch scrollAction {
        case 0: adjustVolume(by: Float(delta > 0 ? 0.05 : -0.05))
        case 1: seek(by: delta > 0 ? shortSeek : -shortSeek)
        default: break
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])
        switch (chars, mods) {
        case (String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), []):
            seek(by: -shortSeek); return true
        case (String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), []):
            seek(by: shortSeek); return true
        case (String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), .shift):
            seek(by: -longSeek); return true
        case (String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), .shift):
            seek(by: longSeek); return true
        case (String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), .command):
            seek(by: -longSeek * 2); return true
        case (String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), .command):
            seek(by: longSeek * 2); return true
        case (String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), []):
            adjustVolume(by: 0.05); return true
        case (String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), []):
            adjustVolume(by: -0.05); return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])

        switch (characters, modifiers) {
        case (" ", []):
            togglePlayPause()
        case ("f", []), ("f", .command):
            onDoubleClick?()
        case ("m", []):
            toggleMute()
        case (String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), []):
            seek(by: -shortSeek)
        case (String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), []):
            seek(by: shortSeek)
        case (String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), .shift):
            seek(by: -longSeek)
        case (String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), .shift):
            seek(by: longSeek)
        case (String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), .command):
            seek(by: -longSeek * 2)
        case (String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), .command):
            seek(by: longSeek * 2)
        case (String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), []):
            adjustVolume(by: 0.05)
        case (String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), []):
            adjustVolume(by: -0.05)
        case ("[", []):
            adjustSpeed(by: -0.25)
        case ("]", []):
            adjustSpeed(by: 0.25)
        case ("\\", []):
            setSpeed(1.0)
        default:
            super.keyDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Playback

    func openFile(url: URL) {
        currentFileURL = url
        welcomeView.isHidden = true
        controlBarView.setVideoActive(true)
        playerEngine?.stop()

        if !playlistManager.items.contains(url) {
            playlistManager.addItem(url)
        }
        playlistManager.selectItem(at: playlistManager.items.firstIndex(of: url) ?? 0)

        let vol = UserDefaults.standard.double(forKey: Defaults.defaultVolume)

        abLoopController.gap = UserDefaults.standard.double(forKey: Defaults.abLoopGap)

        vlcEngine?.stop()
        vlcEngine = nil

        if url.isNativeAVPlayerFormat {
            // Native MP4/MOV — use AVPlayer for Dolby Vision + AirPlay
            let engine = AVPlayerEngine()
            playerEngine = engine
            engine.delegate = self
            engine.volume = Float(vol > 0 ? vol : 1.0)
            controlBarView.setVolume(engine.volume)
            let speed = UserDefaults.standard.double(forKey: Defaults.defaultSpeed)
            if speed > 0 && speed != 1.0 {
                engine.rate = Float(speed)
                controlBarView.setSpeed(Float(speed))
            }
            playWithEngine(engine, url: url, fallbackRemux: false)
        } else {
            // MKV/AVI/WebM — use VLC engine for instant playback
            playerEngine?.stop()
            playerEngine = nil

            let engine = VLCPlayerEngine()
            vlcEngine = engine
            engine.delegate = self

            if engine.open(url: url) {
                // Embed VLC's render view into our video view
                let vlcView = engine.renderView
                vlcView.translatesAutoresizingMaskIntoConstraints = false
                videoView.subviews.forEach { $0.removeFromSuperview() }
                videoView.addSubview(vlcView)
                NSLayoutConstraint.activate([
                    vlcView.topAnchor.constraint(equalTo: videoView.topAnchor),
                    vlcView.bottomAnchor.constraint(equalTo: videoView.bottomAnchor),
                    vlcView.leadingAnchor.constraint(equalTo: videoView.leadingAnchor),
                    vlcView.trailingAnchor.constraint(equalTo: videoView.trailingAnchor),
                ])

                controlBarView.setDuration(engine.duration)
                engine.volume = Float(vol > 0 ? vol : 1.0)
                controlBarView.setVolume(engine.volume)

                let autoPlay = UserDefaults.standard.bool(forKey: Defaults.autoPlayOnOpen)
                if autoPlay {
                    engine.play()
                    controlBarView.setPlaying(true)
                }
            } else {
                osdView.show(message: "Failed to open file")
            }
        }

        // Auto-load matching subtitle files
        if UserDefaults.standard.bool(forKey: Defaults.autoLoadSubtitles) {
            let subs = SubtitleManager.findSubtitleFiles(for: url)
            if let first = subs.first {
                subtitleManager.loadSubtitle(from: first)
            }
        }

        // Evaluate passthrough in background
        Task {
            let info = await MediaInfo.probe(url: url)
            await MainActor.run {
                self.passthroughManager.evaluateForMedia(audioCodec: info.audioCodecName)
            }
        }
    }

    private var playbackStatusObservation: NSKeyValueObservation?

    /// Wires the engine to the video view and waits for .readyToPlay before auto-playing.
    /// We observe the item status here (in addition to AVPlayerEngine's own observation)
    /// because the VC needs to resize the window to match the video's native aspect ratio
    /// — that info is only available after the asset header is parsed.
    private func playWithEngine(_ engine: AVPlayerEngine, url: URL, fallbackRemux: Bool = false) {
        print("[AwesomePlayer] Opening: \(url.path)")
        engine.open(url: url)
        videoView.setPlayer(engine.player)
        controlBarView.setPlayer(engine.player)

        playbackStatusObservation = engine.player?.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else {
                if item.status == .failed {
                    print("[AwesomePlayer] Player item FAILED: \(item.error?.localizedDescription ?? "?")")
                    if fallbackRemux {
                        self?.remuxAndPlay(engine: engine, url: url)
                        return
                    }
                }
                return
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                print("[AwesomePlayer] Ready to play! Duration: \(engine.duration)s")
                self.controlBarView.setDuration(engine.duration)
                let autoPlay = UserDefaults.standard.bool(forKey: Defaults.autoPlayOnOpen)
                if autoPlay {
                    engine.play()
                    self.controlBarView.setPlaying(true)
                }

                // Resize window to fit video at up to 70% of screen, capped at native resolution
                if let window = self.view.window as? PlayerWindow, let videoSize = engine.videoSize {
                    window.setAspectRatio(videoSize)
                    let screenFrame = NSScreen.main?.visibleFrame ?? .zero
                    let scale = min(screenFrame.width * 0.7 / videoSize.width, screenFrame.height * 0.7 / videoSize.height, 1.0)
                    let newSize = NSSize(width: videoSize.width * scale, height: videoSize.height * scale)
                    window.setContentSize(newSize)
                    window.center()
                }
            }
        }
    }


    private func remuxAndPlay(engine: AVPlayerEngine, url: URL) {
        DispatchQueue.main.async {
            self.osdView.show(message: "Loading…", duration: 10.0)
        }
        let fullURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_full")
            .appendingPathExtension("mp4")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = (try? FFmpegBridge.remuxFile(url.path, toOutput: fullURL.path)) != nil
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    let newEngine = AVPlayerEngine()
                    self.playerEngine = newEngine
                    newEngine.delegate = self
                    self.playWithEngine(newEngine, url: fullURL)
                } else {
                    self.osdView.show(message: "Failed to open file")
                }
            }
        }
    }

    func togglePlayPause() {
        if let engine = playerEngine {
            if engine.isPlaying { engine.pause(); osdView.show(message: "Paused") }
            else { engine.play(); osdView.show(message: "Playing") }
            controlBarView.setPlaying(engine.isPlaying)
        } else if let engine = vlcEngine {
            if engine.isPlaying { engine.pause(); osdView.show(message: "Paused") }
            else { engine.play(); osdView.show(message: "Playing") }
            controlBarView.setPlaying(engine.isPlaying)
        }    }

    func seek(by seconds: Double) {
        var newTime: Double = 0
        var dur: Double = 0
        if let engine = playerEngine {
            engine.seek(by: seconds)
            newTime = engine.currentTime
            dur = engine.duration
        } else if let engine = vlcEngine {
            engine.seek(by: seconds)
            newTime = engine.currentTime
            dur = engine.duration
        }
        let pct = dur > 0 ? Int(newTime / dur * 100) : 0
        let cur = formatSeekTime(newTime)
        let total = formatSeekTime(dur)
        osdView.show(message: "Seek to \(cur) / \(total) (\(pct)%)")
    }

    private func formatSeekTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }

    func adjustVolume(by delta: Float) {
        var v: Float = 1
        if let engine = playerEngine {
            v = max(0, min(1, engine.volume + delta)); engine.volume = v
        } else if let engine = vlcEngine {
            v = max(0, min(1, engine.volume + delta)); engine.volume = v
        }
        controlBarView.setVolume(v)
        osdView.show(message: "Volume: \(Int(v * 100))%")
    }

    func toggleMute() {
        if let engine = playerEngine {
            engine.isMuted.toggle()
            controlBarView.setMuted(engine.isMuted)
            osdView.show(message: engine.isMuted ? "Muted" : "Unmuted")
        } else if let engine = vlcEngine {
            engine.isMuted.toggle()
            controlBarView.setMuted(engine.isMuted)
            osdView.show(message: engine.isMuted ? "Muted" : "Unmuted")
        }    }

    func adjustSpeed(by delta: Float) {
        guard let engine = playerEngine else { return }
        let newRate = max(0.25, min(4.0, engine.rate + delta))
        engine.rate = newRate
        controlBarView.setSpeed(newRate)
        osdView.show(message: String(format: "Speed: %.2fx", newRate))
    }

    func setSpeed(_ speed: Float) {
        playerEngine?.rate = speed
        controlBarView.setSpeed(speed)
        osdView.show(message: String(format: "Speed: %.2fx", speed))
    }

    func showControlBar(animated: Bool) {
        if animated {
            controlBarView.animator().alphaValue = 1.0
        } else {
            controlBarView.alphaValue = 1.0
        }
    }

    func hideControlBar(animated: Bool) {
        if animated {
            controlBarView.animator().alphaValue = 0.0
        } else {
            controlBarView.alphaValue = 0.0
        }
    }

    func showOSD(_ message: String, duration: TimeInterval = 1.5) {
        osdView.show(message: message, duration: duration)
    }

    func showAirPlayPicker() {
        controlBarView.showAirPlayPicker()

        // After the user selects a device, check if video streaming activated.
        // If only audio routed, fall back to moving the window to the external display.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self = self,
                  let player = self.playerEngine?.player,
                  !player.isExternalPlaybackActive else { return }
            if NSScreen.screens.count > 1 {
                self.moveToExternalDisplay()
            }
        }
    }

    // MARK: - Subtitle Operations

    func loadSubtitleFile(_ url: URL) {
        subtitleManager.loadSubtitle(from: url)
        osdView.show(message: "Subtitle loaded: \(url.lastPathComponent)")
    }

    func toggleSubtitleVisibility() {
        subtitleManager.toggleVisibility()
        if subtitleManager.isVisible {
            osdView.show(message: "Subtitles visible")
        } else {
            subtitleOverlayView.setText(nil)
            osdView.show(message: "Subtitles hidden")
        }
    }

    func adjustSubtitleDelay(by delta: Double) {
        subtitleManager.adjustDelay(by: delta)
        osdView.show(message: String(format: "Subtitle delay: %.1fs", subtitleManager.delay))
    }

    func resetSubtitleDelay() {
        subtitleManager.delay = 0
        osdView.show(message: "Subtitle delay reset")
    }

    // MARK: - Screenshot

    func saveScreenshot() {
        guard let player = playerEngine?.player, let item = player.currentItem else {
            osdView.show(message: "No video playing")
            return
        }
        let time = player.currentTime()
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var actualTime = CMTime.zero
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: &actualTime) else {
                DispatchQueue.main.async { self?.osdView.show(message: "Screenshot failed") }
                return
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let formatIndex = UserDefaults.standard.integer(forKey: Defaults.screenshotFormat)
            let (fileType, ext): (NSBitmapImageRep.FileType, String) = {
                switch formatIndex {
                case 1: return (.jpeg, "jpg")
                case 2: return (.tiff, "tiff")
                default: return (.png, "png")
                }
            }()
            guard let data = rep.representation(using: fileType, properties: [:]) else { return }
            let saveIndex = UserDefaults.standard.integer(forKey: Defaults.screenshotSavePath)
            let dir: URL = {
                switch saveIndex {
                case 1: return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
                case 2: return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                default: return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                }
            }()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let filename = "Awesome Player \(formatter.string(from: Date())).\(ext)"
            try? data.write(to: dir.appendingPathComponent(filename))
            DispatchQueue.main.async { self?.osdView.show(message: "Screenshot saved to Desktop") }
        }
    }

    // MARK: - Seek & A-B Loop

    func seekToAbsoluteTime(_ seconds: Double) {
        playerEngine?.seekTo(time: seconds)
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        osdView.show(message: String(format: "Jump to %d:%02d", mins, secs))
    }

    func toggleABLoop() {
        guard let player = playerEngine?.player else { return }
        abLoopController.toggle(currentTime: player.currentTime())
        switch abLoopController.state {
        case .inactive:
            osdView.show(message: "A-B Loop cleared")
        case .settingA:
            osdView.show(message: "A point set")
        case .active:
            osdView.show(message: "A-B Loop active")
        }
    }

    // MARK: - Video Size & Transform

    func setVideoWindowSize(scale: CGFloat) {
        guard let window = view.window, let videoSize = playerEngine?.videoSize else {
            osdView.show(message: "No video loaded")
            return
        }
        let newSize = NSSize(width: videoSize.width * scale, height: videoSize.height * scale)
        window.setContentSize(newSize)
        window.center()
        osdView.show(message: scale == 1 ? "Original size" : String(format: "%.0f%% size", scale * 100))
    }

    func fitWindowToScreen() {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        window.setFrame(frame, display: true, animate: true)
        osdView.show(message: "Fit to screen")
    }

    func toggleFillScreen() {
        isFillScreen.toggle()
        videoView.setVideoGravity(isFillScreen ? .resizeAspectFill : .resizeAspect)
        osdView.show(message: isFillScreen ? "Fill screen" : "Fit to screen")
    }

    func setAspectRatio(_ name: String) {
        guard let window = view.window else { return }
        switch name {
        case "4:3":   window.contentAspectRatio = NSSize(width: 4, height: 3)
        case "16:9":  window.contentAspectRatio = NSSize(width: 16, height: 9)
        case "16:10": window.contentAspectRatio = NSSize(width: 16, height: 10)
        case "2.35:1": window.contentAspectRatio = NSSize(width: 235, height: 100)
        case "2.39:1": window.contentAspectRatio = NSSize(width: 239, height: 100)
        default:
            window.resizeIncrements = NSSize(width: 1, height: 1)
            window.contentAspectRatio = NSSize(width: 0, height: 0)
        }
        osdView.show(message: "Aspect ratio: \(name)")
    }

    func rotateVideo(by degrees: CGFloat) {
        videoRotation += degrees
        if videoRotation >= 360 { videoRotation -= 360 }
        if videoRotation < 0 { videoRotation += 360 }
        updateVideoTransform()
        osdView.show(message: "Rotate: \(Int(videoRotation))°")
    }

    func flipVideo(horizontal: Bool) {
        if horizontal {
            videoFlippedH.toggle()
        } else {
            videoFlippedV.toggle()
        }
        updateVideoTransform()
        osdView.show(message: horizontal ? "Flip horizontal" : "Flip vertical")
    }

    func revertVideoTransform() {
        videoRotation = 0
        videoFlippedH = false
        videoFlippedV = false
        updateVideoTransform()
        osdView.show(message: "Transform reset")
    }

    private func updateVideoTransform() {
        var t = CATransform3DIdentity
        t = CATransform3DRotate(t, videoRotation * .pi / 180, 0, 0, 1)
        if videoFlippedH { t = CATransform3DScale(t, -1, 1, 1) }
        if videoFlippedV { t = CATransform3DScale(t, 1, -1, 1) }
        videoView.setLayerTransform(t)
    }

    // MARK: - Picture in Picture

    func togglePiP() {
        if pipController == nil, let layer = videoView.getPlayerLayer() {
            pipController = AVPictureInPictureController(playerLayer: layer)
        }
        guard let pip = pipController else {
            osdView.show(message: "PiP not available")
            return
        }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    // MARK: - Audio Sync

    func adjustAudioDelay(by delta: Double) {
        audioDelayOffset += delta
        osdView.show(message: String(format: "Audio delay: %+.1fs", audioDelayOffset))
    }

    func resetAudioDelay() {
        audioDelayOffset = 0
        osdView.show(message: "Audio delay reset")
    }

    // MARK: - Playlist

    func setRepeatMode(_ mode: RepeatMode) {
        playlistManager.repeatMode = mode
        osdView.show(message: "Repeat: \(mode.rawValue)")
    }

    func toggleShuffle() {
        playlistManager.shuffle.toggle()
        osdView.show(message: playlistManager.shuffle ? "Shuffle on" : "Shuffle off")
    }

    func playNextTrack() {
        guard let url = playlistManager.next() else {
            osdView.show(message: "No next track")
            return
        }
        onFileDropped?(url)
    }

    func playPreviousTrack() {
        guard let url = playlistManager.previous() else {
            osdView.show(message: "No previous track")
            return
        }
        onFileDropped?(url)
    }
}

// MARK: - ControlBarDelegate

extension PlayerViewController: ControlBarDelegate {
    func controlBarPlayPauseClicked() {
        togglePlayPause()
    }

    func controlBarSeekRequested(to fraction: Double) {
        if let engine = playerEngine {
            engine.seekToFraction(fraction)
        } else if let engine = vlcEngine {
            engine.seekToFraction(fraction)
        }    }

    func controlBarVolumeChanged(to volume: Float) {
        playerEngine?.volume = volume
        osdView.show(message: "Volume: \(Int(volume * 100))%")
    }

    func controlBarSpeedChanged(to speed: Float) {
        setSpeed(speed)
    }

    func controlBarSeekBackward() {
        seek(by: -5)
    }

    func controlBarSeekForward() {
        seek(by: 5)
    }
}

// MARK: - AVPlayerEngineDelegate

extension PlayerViewController: AVPlayerEngineDelegate {
    func playerEngineTimeDidChange(current: Double, duration: Double) {
        controlBarView.updateTime(current: current, duration: duration)

        if subtitleManager.hasSubtitles, subtitleManager.isVisible,
           let entry = subtitleManager.subtitle(at: current) {
            subtitleOverlayView.setText(entry.text)
        } else {
            subtitleOverlayView.setText(nil)
        }

        if let player = playerEngine?.player {
            abLoopController.checkLoop(currentTime: player.currentTime())
        }
    }

    func playerEngineDidFinishPlaying() {
        controlBarView.setPlaying(false)
        let action = UserDefaults.standard.integer(forKey: Defaults.mediaEndAction)
        switch action {
        case 1: // Close Media
            playerEngine?.stop()
            welcomeView.isHidden = false
            controlBarView.setVideoActive(false)
        case 2: // Play Next
            playNextTrack()
        case 3: // Loop
            playerEngine?.seekTo(time: 0)
            playerEngine?.play()
            controlBarView.setPlaying(true)
        default: break
        }
    }

    func playerEngineDidUpdateStatus(isPlaying: Bool) {
        controlBarView.setPlaying(isPlaying)
        onPlaybackStateChanged?(isPlaying)
    }

    func playerEngineExternalPlaybackChanged(isActive: Bool) {
        if isActive {
            osdView.show(message: "AirPlay: Playing on TV", duration: 3.0)
        } else {
            osdView.show(message: "AirPlay: Local playback")
        }
    }

    /// Move the player window to an external display and enter fullscreen.
    /// Works with HDMI, AirPlay displays, and sidecar — any screen that macOS
    /// recognizes. Falls back to a helpful message if no external screen exists.
    func moveToExternalDisplay() {
        guard let window = view.window else { return }
        guard let externalScreen = NSScreen.screens.first(where: { $0 != NSScreen.main }) else {
            osdView.show(message: "No external display found — add one via System Settings > Displays", duration: 3.0)
            return
        }
        window.setFrame(externalScreen.frame, display: true, animate: true)
        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        osdView.show(message: "Playing on \(externalScreen.localizedName)", duration: 3.0)
    }
}

// MARK: - VLCPlayerEngineDelegate

extension PlayerViewController: VLCPlayerEngineDelegate {
    func vlcEngineTimeDidChange(current: Double, duration: Double) {
        controlBarView.updateTime(current: current, duration: duration)
    }
    func vlcEngineDidFinishPlaying() {
        controlBarView.setPlaying(false)
    }
    func vlcEngineDidUpdateStatus(isPlaying: Bool) {
        controlBarView.setPlaying(isPlaying)
        onPlaybackStateChanged?(isPlaying)
    }
}

// MARK: - AudioPassthroughManagerDelegate

extension PlayerViewController: AudioPassthroughManagerDelegate {
    func passthroughStateChanged(isActive: Bool, deviceName: String?) {
        if isActive {
            osdView.show(message: "Passthrough: ON (\(deviceName ?? "Unknown"))")
        } else {
            osdView.show(message: "Passthrough: OFF")
        }
    }

    func togglePassthrough() {
        passthroughManager.toggle()
    }
}

// MARK: - ABLoopDelegate

extension PlayerViewController: ABLoopDelegate {
    func abLoopStateChanged(_ state: ABLoopState) {}

    func abLoopShouldSeek(to time: CMTime) {
        playerEngine?.player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

/// Separate view for drag-and-drop so the root view owns the drag registration
/// independently of PlayerViewController's subview hierarchy.
// MARK: - Drag and Drop View

class DragDropView: NSView {
    var onFileDropped: ((URL) -> Void)?
    var onArrowKey: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func keyDown(with event: NSEvent) {
        // Must override to prevent system beep on arrow keys
        if let chars = event.charactersIgnoringModifiers,
           let scalar = chars.unicodeScalars.first?.value,
           scalar >= NSUpArrowFunctionKey && scalar <= NSRightArrowFunctionKey {
            onArrowKey?(Int(scalar))
        } else {
            super.keyDown(with: event)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first else {
            return false
        }
        onFileDropped?(url)
        return true
    }
}
