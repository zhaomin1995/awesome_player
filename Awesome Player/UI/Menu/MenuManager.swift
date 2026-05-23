import Cocoa

class MenuManager {
    static func setupMainMenu() {
        let mainMenu = NSMenu()

        mainMenu.addItem(createAppMenu())
        mainMenu.addItem(createFileMenu())
        mainMenu.addItem(createPlaybackMenu())
        mainMenu.addItem(createAudioMenu())
        mainMenu.addItem(createVideoMenu())
        mainMenu.addItem(createSubtitleMenu())
        mainMenu.addItem(createPlaylistMenu())
        mainMenu.addItem(createCastMenu())
        mainMenu.addItem(createWindowMenu())
        mainMenu.addItem(createHelpMenu())

        NSApplication.shared.mainMenu = mainMenu
    }

    private static func createAppMenu() -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu()

        menu.addItem(withTitle: "About Awesome Player", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApplication.shared.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Awesome Player", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Awesome Player", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createFileMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "File")

        menu.addItem(withTitle: "Open File…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        menu.addItem(withTitle: "Open URL…", action: #selector(AppDelegate.openURL(_:)), keyEquivalent: "u")

        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Add Subtitle File…", action: #selector(AppDelegate.addSubtitleFile(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save Screenshot", action: #selector(AppDelegate.saveScreenshot(_:)), keyEquivalent: "s")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.close), keyEquivalent: "w")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createPlaybackMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Playback", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Playback")

        menu.addItem(withTitle: "Play / Pause", action: #selector(AppDelegate.togglePlayPause(_:)), keyEquivalent: " ")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Seek Forward 5s", action: #selector(AppDelegate.seekForward5(_:)), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        menu.addItem(withTitle: "Seek Backward 5s", action: #selector(AppDelegate.seekBackward5(_:)), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))

        menu.addItem(.separator())
        menu.addItem(withTitle: "Jump to Time…", action: #selector(AppDelegate.jumpToTime(_:)), keyEquivalent: "j")

        menu.addItem(.separator())
        let speedMenu = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        let speedSubmenu = NSMenu(title: "Speed")
        for speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            speedSubmenu.addItem(withTitle: String(format: "%.2gx", speed), action: #selector(AppDelegate.setSpeed(_:)), keyEquivalent: "")
        }
        speedMenu.submenu = speedSubmenu
        menu.addItem(speedMenu)

        menu.addItem(.separator())
        menu.addItem(withTitle: "A-B Repeat", action: #selector(AppDelegate.toggleABRepeat(_:)), keyEquivalent: "r")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createAudioMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Audio", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Audio")

        menu.addItem(withTitle: "Volume Up", action: #selector(AppDelegate.volumeUp(_:)), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        menu.addItem(withTitle: "Volume Down", action: #selector(AppDelegate.volumeDown(_:)), keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        menu.addItem(withTitle: "Mute", action: #selector(AppDelegate.toggleMute(_:)), keyEquivalent: "m")
        menu.addItem(.separator())

        let tracksItem = NSMenuItem(title: "Audio Tracks", action: nil, keyEquivalent: "")
        tracksItem.submenu = NSMenu(title: "Audio Tracks")
        menu.addItem(tracksItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Equalizer", action: #selector(AppDelegate.showAudioPanel(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Passthrough", action: #selector(AppDelegate.togglePassthrough(_:)), keyEquivalent: "p")

        let deviceItem = NSMenuItem(title: "Output Device", action: nil, keyEquivalent: "")
        deviceItem.submenu = NSMenu(title: "Output Device")
        menu.addItem(deviceItem)

        menuItem.submenu = menu
        return menuItem
    }

    private static func createVideoMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Video", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Video")

        let aspectItem = NSMenuItem(title: "Aspect Ratio", action: nil, keyEquivalent: "")
        let aspectMenu = NSMenu(title: "Aspect Ratio")
        for ratio in ["Default", "4:3", "16:9", "16:10", "2.35:1", "Fill Screen"] {
            aspectMenu.addItem(withTitle: ratio, action: #selector(AppDelegate.setAspectRatio(_:)), keyEquivalent: "")
        }
        aspectItem.submenu = aspectMenu
        menu.addItem(aspectItem)

        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu(title: "Size")
        sizeMenu.addItem(withTitle: "Half Size", action: #selector(AppDelegate.setHalfSize(_:)), keyEquivalent: "")
        sizeMenu.addItem(withTitle: "Original Size", action: #selector(AppDelegate.setOriginalSize(_:)), keyEquivalent: "")
        sizeMenu.addItem(withTitle: "Double Size", action: #selector(AppDelegate.setDoubleSize(_:)), keyEquivalent: "")
        sizeMenu.addItem(withTitle: "Fit to Screen", action: #selector(AppDelegate.fitToScreen(_:)), keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Video Equalizer", action: #selector(AppDelegate.showVideoEQ(_:)), keyEquivalent: "e")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Picture in Picture", action: #selector(AppDelegate.togglePiP(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createSubtitleMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Subtitle", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Subtitle")

        menu.addItem(withTitle: "Show / Hide Subtitles", action: #selector(AppDelegate.toggleSubtitles(_:)), keyEquivalent: "s")
        menu.addItem(.separator())

        let tracksItem = NSMenuItem(title: "Subtitle Tracks", action: nil, keyEquivalent: "")
        tracksItem.submenu = NSMenu(title: "Subtitle Tracks")
        menu.addItem(tracksItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Add Subtitle File…", action: #selector(AppDelegate.addSubtitleFile(_:)), keyEquivalent: "")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createPlaylistMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Playlist", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Playlist")

        menu.addItem(withTitle: "Repeat Off", action: #selector(AppDelegate.setRepeatOff(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Repeat One", action: #selector(AppDelegate.setRepeatOne(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Repeat All", action: #selector(AppDelegate.setRepeatAll(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Shuffle", action: #selector(AppDelegate.toggleShuffle(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Previous", action: #selector(AppDelegate.previousTrack(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Next", action: #selector(AppDelegate.nextTrack(_:)), keyEquivalent: "")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createCastMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Cast", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Cast")

        menu.addItem(withTitle: "AirPlay", action: #selector(AppDelegate.showAirPlay(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Chromecast", action: #selector(AppDelegate.showChromecast(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "DLNA", action: #selector(AppDelegate.showDLNA(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Disconnect", action: #selector(AppDelegate.disconnectCast(_:)), keyEquivalent: "")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createWindowMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Window")

        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Keep on Top", action: #selector(AppDelegate.toggleAlwaysOnTop(_:)), keyEquivalent: "t")

        NSApplication.shared.windowsMenu = menu
        menuItem.submenu = menu
        return menuItem
    }

    private static func createHelpMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Help")
        menu.addItem(withTitle: "Awesome Player Help", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?")
        NSApplication.shared.helpMenu = menu
        menuItem.submenu = menu
        return menuItem
    }
}
