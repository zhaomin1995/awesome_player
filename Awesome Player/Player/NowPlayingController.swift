import Cocoa
import MediaPlayer
import AVFoundation

class NowPlayingController {
    weak var playerViewController: PlayerViewController?

    /// Stores the (command, handler) pairs registered in `setup()` so `deinit`
    /// can `removeTarget` each one. AppDelegate only ever creates one instance
    /// for the app's lifetime today, so this isn't a runtime leak — but if
    /// anyone ever re-instantiates the controller (e.g. a test or a future
    /// "reset playback" flow) the handlers would accumulate without cleanup.
    private var registeredHandlers: [(command: MPRemoteCommand, target: Any)] = []

    func setup() {
        let cc = MPRemoteCommandCenter.shared()

        register(cc.playCommand) { [weak self] _ in
            self?.playerViewController?.togglePlayPause(); return .success
        }
        register(cc.pauseCommand) { [weak self] _ in
            self?.playerViewController?.togglePlayPause(); return .success
        }
        register(cc.togglePlayPauseCommand) { [weak self] _ in
            self?.playerViewController?.togglePlayPause(); return .success
        }
        register(cc.nextTrackCommand) { [weak self] _ in
            self?.playerViewController?.playNextTrack(); return .success
        }
        register(cc.previousTrackCommand) { [weak self] _ in
            self?.playerViewController?.playPreviousTrack(); return .success
        }
        cc.skipForwardCommand.preferredIntervals = [15]
        register(cc.skipForwardCommand) { [weak self] event in
            guard let e = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            self?.playerViewController?.seek(by: e.interval)
            return .success
        }
        cc.skipBackwardCommand.preferredIntervals = [15]
        register(cc.skipBackwardCommand) { [weak self] event in
            guard let e = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            self?.playerViewController?.seek(by: -e.interval)
            return .success
        }
        register(cc.changePlaybackPositionCommand) { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.playerViewController?.seekToAbsoluteTime(e.positionTime)
            return .success
        }
    }

    deinit {
        for (command, target) in registeredHandlers {
            command.removeTarget(target)
        }
    }

    private func register(_ command: MPRemoteCommand,
                          handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        let target = command.addTarget(handler: handler)
        registeredHandlers.append((command, target))
    }

    func updateNowPlaying(title: String, duration: Double, artwork: NSImage? = nil) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        if let image = artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updateTime(elapsed: Double, rate: Double) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updatePlaybackState(isPlaying: Bool) {
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
