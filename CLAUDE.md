# Awesome Player - macOS Video Player

## Project Overview
A full-featured macOS video player combining Dolby Vision playback with AirPlay streaming, inspired by Movist Pro's UI and VLC's codec breadth. Built with AppKit + AVFoundation + FFmpeg.

## Architecture

### Dual-Engine Playback
- **Engine 1 (AVPlayer)**: For H.264, HEVC, AAC, AC3 — gets native Dolby Vision + AirPlay
- **Engine 2 (FFmpeg decoder)**: For VP9, DivX, WMV, etc. — software decode (planned)
- **MKV support**: FFmpeg remuxes MKV to temp MP4 (transcodes Vorbis→AAC), then AVPlayer plays it

### Key Technical Decisions
- All playback routes through AVPlayer when possible for native DV/AirPlay
- FFmpeg is bundled in `Vendor/ffmpeg/` (built from source, no Homebrew dependency)
- Obj-C bridging (`FFmpegBridge.h/m`) wraps FFmpeg C APIs for Swift
- Audio FIFO (`AVAudioFifo`) ensures correct 1024-sample AAC frame sizes during Vorbis→AAC transcoding
- Control bar is transparent on welcome screen, opaque dark when playing

### Directory Structure
```
Awesome Player/
├── App/            # AppDelegate, main.swift, Info.plist
├── Player/         # AVPlayerEngine, PlayerEngine, ABLoopController, VideoEQProcessor
├── Audio/          # AudioEngine, Equalizer, Compressor, Spatializer, PitchShifter, Passthrough
├── Casting/        # CastingManager, Chromecast, DLNA, HTTP server
├── Media/          # MediaInfo, SubtitleParser/Manager, PlaylistManager
├── FFmpeg/         # FFmpegBridge (Obj-C), bridging header
├── UI/
│   ├── Window/     # PlayerWindow (borderless), PlayerWindowController, TitleBarView
│   ├── Player/     # PlayerViewController, VideoView, SubtitleOverlayView, WelcomeView
│   ├── Controls/   # ControlBarView, SeekSlider, Volume, Playback, Speed, Cast, ABLoop
│   ├── Panels/     # PanelContainer, Playlist, Audio, Subtitle, Video, MediaInfo, Cast panels
│   ├── OSD/        # On-screen display messages
│   ├── Menu/       # MenuManager (10 menus, Movist Pro style)
│   └── Preferences/# 11-tab preferences window
└── Utilities/      # Extensions, Defaults, GradientScrimView
```

### Build Requirements
- macOS 14.0+ target
- Xcode (Swift 5 + Obj-C)
- FFmpeg bundled in `Vendor/ffmpeg/` (run `Scripts/build_ffmpeg.sh` to rebuild)
- No external dependencies required — fully self-contained

### FFmpeg Integration
- Headers: `Vendor/ffmpeg/include/`
- Dylibs: `Vendor/ffmpeg/lib/`
- Bridging: `Awesome Player/FFmpeg/FFmpegBridge.m` (Obj-C wrapper)
- Must add Xcode Run Script build phase to copy dylibs to `Contents/Frameworks/`

### UI Design (Movist Pro Style)
- Borderless window with transparent title bar
- Dark radial gradient welcome screen (dark center → lighter edges)
- Control bar: opaque dark when playing, transparent on welcome
- Auto-hide controls after 3s idle
- Movist Pro-style dropdown menus for Video/Audio/Subtitle

## Development Guidelines

### Code Quality
- Every time you make changes, ensure comment coverage is good for readability and maintainability
- Update this CLAUDE.md file if architectural decisions change or new features are added
- Add comments explaining WHY, not WHAT — the code should be self-documenting for the WHAT
- Document non-obvious constraints, workarounds, and codec-specific behaviors

### Testing
- Test with MP4 (native path) and MKV (remux path) files
- Verify audio works for MKV files with Vorbis audio (transcoded to AAC)
- Check control bar appearance on both welcome screen and during playback
- Test keyboard shortcuts: Space, arrows, M, F, etc.

### Common Pitfalls
- FFmpeg dylibs must be in app's `Contents/Frameworks/` at runtime (Xcode build phase)
- `AVAssetResourceLoaderDelegate` approach was planned but temp-file remux is simpler
- AAC encoder needs exact 1024-sample frames via AVAudioFifo (not direct from decoder)
- `contentAspectRatio` on NSWindow locks resize — removed for free resizing
- `@main` on AppDelegate doesn't work without MainMenu.nib — use explicit `main.swift`

### Git Repository
- Repo: https://github.com/zhaomin1995/awesome_player (renamed from video_player)
- Branch: main
- All FFmpeg vendor files are committed (no build step needed after clone)
