# Awesome Player - macOS Video Player

## Project Overview
A full-featured macOS video player combining Dolby Vision playback with AirPlay streaming, Chromecast casting, DLNA, and VLC-quality codec support. Inspired by Movist Pro's polished UI and VLC's codec breadth. Built with AppKit + AVFoundation + libvlc + FFmpeg.

## Architecture

### Dual-Engine Playback
- **AVPlayer**: For native MP4/MOV with H.264/HEVC — gets Dolby Vision, HDR10, HLG, AirPlay, and PiP
- **libvlc (VLC engine)**: For MKV, AVI, WebM, and any codec VLC supports — instant playback, no remuxing
- FFmpeg's `FFmpegBridge` is used for media probing, codec identification, track enumeration, embedded subtitle extraction, and as a fallback remuxer
- Both engines share a common control surface: SubtitleManager, ABLoopController, NowPlayingController, ResumeManager, PlaylistManager, OSDView

### Directory Structure
```
Awesome Player/
├── App/            # AppDelegate, main.swift, Info.plist, AppIcon
├── Player/         # AVPlayerEngine, VLCPlayerEngine, ABLoopController,
│                   # NowPlayingController, ResumeManager
├── Audio/          # AudioEqualizer (presets), AudioPassthrough, AudioPassthroughManager
├── Casting/        # CastingManager, ChromecastManager (Cast V2), DLNAManager, CastingHTTPServer
├── Media/          # MediaInfo, SubtitleParser/Manager, PlaylistManager
├── FFmpeg/         # FFmpegBridge (Obj-C prober/remuxer/subtitle extractor), bridging header
├── UI/
│   ├── Window/     # PlayerWindow (borderless), PlayerWindowController, TitleBarView (badges)
│   ├── Player/     # PlayerViewController, VideoView, SubtitleOverlayView, WelcomeView,
│   │               # PlaylistPanelView, VideoEQPanelController, MediaInspectorController
│   ├── Controls/   # ControlBarView, SeekSliderView, VolumeSliderView, PlaybackButtons,
│   │               # SpeedButton, CastButton
│   ├── OSD/        # OSDView (on-screen display messages)
│   ├── Menu/       # MenuManager (all menus with stateful checkmarks),
│   │               # AudioDeviceMenuDelegate, AirPlayMenuDelegate, ChromecastMenuDelegate,
│   │               # RecentDocumentsMenuDelegate, TrackMenuDelegate (audio/video/subtitle)
│   └── Preferences/# PreferencesWindowController (9-tab with animated resizing)
└── Utilities/      # Extensions, Defaults (90+ preference keys across 9 categories)
Vendor/
├── ffmpeg/         # Bundled FFmpeg headers + dylibs
└── libvlc/         # Bundled libvlc headers, dylibs, plugins, libvlc_compat.h
```

### Build & Run
- macOS 14.0+ target, Xcode (Swift 5 + Obj-C)
- **Fully self-contained** — all dependencies bundled in `Vendor/`
- Build phase script auto-copies FFmpeg dylibs, libvlc dylibs, VLC plugins, and app icon
- Just clone, open in Xcode, and Cmd+R

### Key Technical Decisions
- AVPlayer for native formats preserves Dolby Vision and AirPlay
- libvlc for non-native formats gives VLC-identical playback quality
- Singleton VLC instance reused across file opens for fast startup
- libvlc_compat.h expanded to 90+ API declarations (track switching, EQ, audio delay, video adjust, deinterlace, crop, snapshot, subtitle SPU)
- FFmpegBridge wraps FFmpeg C APIs via Obj-C bridging header
- FFmpegBridge.videoCodecNameForFile() for codec badge display on non-native formats
- FFmpegBridge.extractSubtitleTrack() for embedded text subtitle extraction to SRT string
- FFmpegBridge.audioTracksForFile() and subtitleTracksForFile() for Media Inspector track enumeration
- UserDefaults-based Open Recent (custom RecentDocumentsMenuDelegate) because NSDocumentController requires document architecture
- MPRemoteCommandCenter for Now Playing / media keys (works on macOS 10.12.2+)
- NowPlayingController handles play/pause/toggle, skip forward/backward, next/previous track, and scrub position
- ResumeManager with VLC-style smart thresholds (3min duration, 5-95% position, 1min absolute, 1min remaining)
- TrackMenuDelegate dynamically queries active engine (AVPlayer or VLC) for tracks on menu open
- ASS style section parsing (V4+ Styles) produces NSAttributedString with font/color/bold/italic
- ASS color format (&HAABBGGRR) correctly parsed to NSColor with BGR byte order
- Chromecast uses Cast V2 protocol (protobuf over TLS, port 8009) with friendly name extraction from Bonjour TXT record "fn" key
- Audio passthrough detects AC3/E-AC3 capable devices via CoreAudio transport type inspection
- AudioDeviceMenuDelegate filters out virtual and aggregate audio devices using kAudioDevicePropertyTransportType
- All preference controls bound to UserDefaults via Cocoa Bindings
- Menu checkmarks track state (EQ preset, speed, aspect ratio, deinterlace mode, crop, subtitle position, etc.)
- Defaults enum has 90+ keys organized into 9 categories matching the 9 preference tabs
- VideoEQPanelController is a floating NSPanel that adjusts VLC video_adjust parameters in real-time
- MediaInspectorController is a floating NSPanel that probes the current file via FFmpegBridge
- yt-dlp resolution for non-direct-media URLs (checks /opt/homebrew/bin, /usr/local/bin, /usr/bin)

## Development Guidelines

### Code Quality
- Keep good comment coverage — explain WHY, not WHAT
- Update this CLAUDE.md when architecture changes
- Run `xcodebuild` after every change to verify compilation
- Test with both MP4 (AVPlayer path) and MKV (VLC path) files

### Common Pitfalls
- FFmpeg + libvlc dylibs must be in app bundle at runtime (build phase handles this)
- `@main` on AppDelegate doesn't work without MainMenu.nib — use explicit `main.swift`
- libvlc headers are 3.x compatible (`libvlc_compat.h`) — don't use 4.x headers
- VLC plugin path must be set via `VLC_PLUGIN_PATH` env var before `libvlc_new()`
- `CFBundleIconFile` in Info.plist must match the .icns filename (no extension)
- VLC instance is a singleton (`sharedVLCInstance`) — don't call libvlc_release on it during normal playback; only in deinit
- `isPaused` checks AVPlayer rate (rate == 0) on the AVPlayer path; VLC path uses its own `isPlaying` flag
- Subtitle preferences (font/size/color) are live-updated via KVO observers on UserDefaults
- Window drag-and-drop is registered on the DragDropView (which is the root view of PlayerViewController), not on PlayerWindow or individual subviews
- RecentDocumentsMenuDelegate manages its own UserDefaults key because NSDocumentController requires the document-based app architecture
- TrackMenuDelegate has three static instances (.audio, .video, .subtitle) — each wired to a different submenu
- Video adjustments (brightness/contrast/saturation/hue/gamma) require enabling `libvlc_adjust_Enable` before setting float values
- Audio delay is in microseconds in libvlc but exposed as seconds in VLCPlayerEngine API
- Subtitle delay step is in seconds; audio delay step is in milliseconds (converted to seconds before applying)
- Chromecast menu extracts IPv4 address from resolved Bonjour addresses to avoid mDNS hostname resolution issues

### Git Repository
- Repo: https://github.com/zhaomin1995/video_player
- Branch: main
