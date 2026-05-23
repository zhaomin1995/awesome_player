import Foundation

enum Defaults {
    // MARK: - General
    static let theme = "general.theme" // "system", "dark", "light"
    static let transparentTitleBar = "general.transparentTitleBar"
    static let resumePlayback = "general.resumePlayback"
    static let quitOnLastWindowClosed = "general.quitOnLastWindowClosed"

    // MARK: - Media Open
    static let defaultEngine = "mediaOpen.defaultEngine" // "auto", "avplayer", "ffmpeg"
    static let autoFindSeriesFiles = "mediaOpen.autoFindSeriesFiles"
    static let autoLoadSubtitles = "mediaOpen.autoLoadSubtitles"
    static let autoLoadNextFile = "mediaOpen.autoLoadNextFile"
    static let openInNewWindow = "mediaOpen.openInNewWindow"

    // MARK: - Playback
    static let defaultSpeed = "playback.defaultSpeed"
    static let shortSeekInterval = "playback.shortSeekInterval"
    static let longSeekInterval = "playback.longSeekInterval"
    static let keyFrameSeeking = "playback.keyFrameSeeking"
    static let autoPlayOnOpen = "playback.autoPlayOnOpen"
    static let mediaEndAction = "playback.mediaEndAction" // "nothing", "close", "next", "loop"
    static let abLoopGap = "playback.abLoopGap"

    // MARK: - Playlist
    static let repeatMode = "playlist.repeatMode" // "off", "one", "all"
    static let shuffle = "playlist.shuffle"
    static let playlistEndAction = "playlist.endAction"
    static let autoAddFromDirectory = "playlist.autoAddFromDirectory"

    // MARK: - Video
    static let defaultAspectRatio = "video.defaultAspectRatio"
    static let defaultVideoSize = "video.defaultVideoSize"
    static let screenshotFormat = "video.screenshotFormat"
    static let screenshotSavePath = "video.screenshotSavePath"
    static let hdrToneMappingMode = "video.hdrToneMappingMode"

    // MARK: - Audio
    static let defaultOutputDevice = "audio.defaultOutputDevice"
    static let defaultVolume = "audio.defaultVolume"
    static let extendedVolume = "audio.extendedVolume"
    static let passthroughMode = "audio.passthroughMode" // "auto", "on", "off"
    static let defaultEQPreset = "audio.defaultEQPreset"
    static let normalizationTarget = "audio.normalizationTarget"

    // MARK: - Subtitle
    static let subtitleLanguage = "subtitle.language"
    static let autoLoadEmbedded = "subtitle.autoLoadEmbedded"
    static let autoLoadExternal = "subtitle.autoLoadExternal"
    static let defaultEncoding = "subtitle.defaultEncoding"
    static let subtitleFont = "subtitle.font"
    static let subtitleFontSize = "subtitle.fontSize"
    static let subtitleColor = "subtitle.color"
    static let subtitlePosition = "subtitle.position"
    static let subtitleDelayStep = "subtitle.delayStep"

    // MARK: - Full Screen
    static let autoEnterFullscreen = "fullscreen.autoEnter"
    static let pauseOnExitFullscreen = "fullscreen.pauseOnExit"
    static let playOnEnterFullscreen = "fullscreen.playOnEnter"
    static let blackOutOtherScreens = "fullscreen.blackOutOthers"
    static let fullscreenControlBar = "fullscreen.controlBarBehavior"

    // MARK: - Keyboard
    static let mediaKeyEnabled = "keyboard.mediaKeyEnabled"
    static let escapeKeyBehavior = "keyboard.escapeKeyBehavior"

    // MARK: - Mouse
    static let singleClickAction = "mouse.singleClickAction"
    static let doubleClickAction = "mouse.doubleClickAction"
    static let middleClickAction = "mouse.middleClickAction"
    static let scrollWheelAction = "mouse.scrollWheelAction"
    static let scrollWheelSensitivity = "mouse.scrollWheelSensitivity"

    // MARK: - Cast
    static let castDefaultBehavior = "cast.defaultBehavior"
    static let chromecastQuality = "cast.chromecastQuality"
    static let dlnaQuality = "cast.dlnaQuality"
    static let autoDisconnectOnClose = "cast.autoDisconnectOnClose"
    static let resumeLocalOnDisconnect = "cast.resumeLocalOnDisconnect"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            theme: "system",
            transparentTitleBar: true,
            resumePlayback: true,
            quitOnLastWindowClosed: true,
            defaultEngine: "auto",
            autoLoadSubtitles: true,
            autoPlayOnOpen: true,
            defaultSpeed: 1.0,
            shortSeekInterval: 5.0,
            longSeekInterval: 30.0,
            mediaEndAction: "nothing",
            abLoopGap: 0.0,
            repeatMode: "off",
            shuffle: false,
            defaultVolume: 1.0,
            extendedVolume: false,
            passthroughMode: "auto",
            defaultEQPreset: "flat",
            normalizationTarget: -14.0,
            autoLoadEmbedded: true,
            autoLoadExternal: true,
            defaultEncoding: "UTF-8",
            subtitleFontSize: 24.0,
            subtitlePosition: "bottom",
            subtitleDelayStep: 0.1,
            autoEnterFullscreen: false,
            mediaKeyEnabled: true,
            singleClickAction: "playPause",
            doubleClickAction: "fullscreen",
            scrollWheelAction: "volume",
            autoDisconnectOnClose: true,
            resumeLocalOnDisconnect: true,
        ])
    }
}
