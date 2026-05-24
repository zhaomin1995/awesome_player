# Awesome Player - macOS Video Player

## Project Overview
A full-featured macOS video player combining Dolby Vision playback with AirPlay streaming. Inspired by Movist Pro's polished UI and VLC's codec breadth. Built with AppKit + AVFoundation + libvlc + FFmpeg.

## Architecture

### Dual-Engine Playback
- **AVPlayer**: For native MP4/MOV with H.264/HEVC — gets Dolby Vision, HDR10, HLG, and AirPlay
- **libvlc (VLC engine)**: For MKV, AVI, WebM, and any codec VLC supports — instant playback, no remuxing
- FFmpeg's `FFmpegBridge` is still used for media probing and as a fallback remuxer

### Directory Structure
```
Awesome Player/
├── App/            # AppDelegate, main.swift, Info.plist, AppIcon
├── Player/         # AVPlayerEngine, VLCPlayerEngine, ABLoopController
├── Audio/          # AudioEqualizer (presets), AudioPassthrough, AudioPassthroughManager
├── Casting/        # CastingManager, ChromecastManager (Cast V2), DLNAManager, HTTP server
├── Media/          # MediaInfo, SubtitleParser/Manager, PlaylistManager
├── FFmpeg/         # FFmpegBridge (Obj-C remuxer/prober), bridging header
├── UI/
│   ├── Window/     # PlayerWindow (borderless), PlayerWindowController, TitleBarView
│   ├── Player/     # PlayerViewController, VideoView, SubtitleOverlayView, WelcomeView
│   ├── Controls/   # ControlBarView, SeekSlider, Volume, Playback, Speed, CastButton
│   ├── OSD/        # On-screen display messages
│   ├── Menu/       # MenuManager (all menus with stateful checkmarks)
│   └── Preferences/# 9-tab preferences window with animated resizing
└── Utilities/      # Extensions, Defaults (70+ preference keys)
Vendor/
├── ffmpeg/         # Bundled FFmpeg headers + dylibs
└── libvlc/         # Bundled libvlc headers, dylibs, and plugins
```

### Build & Run
- macOS 14.0+ target, Xcode (Swift 5 + Obj-C)
- **Fully self-contained** — all dependencies bundled in `Vendor/`
- Build phase script auto-copies FFmpeg dylibs, libvlc dylibs, VLC plugins, and app icon
- Just clone, open in Xcode, and Cmd+R

### Key Technical Decisions
- AVPlayer for native formats preserves Dolby Vision and AirPlay
- libvlc for non-native formats gives VLC-identical playback quality
- FFmpegBridge wraps FFmpeg C APIs via Obj-C bridging header
- Chromecast uses Cast V2 protocol (protobuf over TLS, port 8009)
- Audio passthrough detects AC3/E-AC3 capable devices via CoreAudio
- All preference controls bound to UserDefaults via Cocoa Bindings
- Menu checkmarks track state (EQ preset, speed, aspect ratio, etc.)

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

### Git Repository
- Repo: https://github.com/zhaomin1995/video_player
- Branch: main
