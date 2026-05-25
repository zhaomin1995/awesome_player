# Awesome Player

A full-featured macOS video player that combines **Dolby Vision** playback with **VLC-quality codec support** — instant MKV playback, AirPlay streaming, Chromecast casting, DLNA, and a polished Movist Pro-style UI. Built entirely with AppKit (no storyboards), AVFoundation, libvlc, and FFmpeg.

## Features

### Playback
- **Instant MKV/AVI/WebM playback** via integrated libvlc — no remuxing, no delay
- **Dolby Vision / HDR10 / HLG** for native MP4/MOV via AVPlayer + VideoToolbox
- **30+ container formats** and all codecs VLC supports (H.264, HEVC, VP9, AV1, etc.)
- Keyboard shortcuts: Space (play/pause), arrows (seek/volume), M (mute), F (fullscreen), `[` `]` (speed), `.` `,` (frame step), Escape (configurable behavior)
- A-B loop with configurable gap
- Playback speed control (0.25x-4x) with menu and keyboard shortcuts
- Frame-by-frame stepping forward (`.`) and backward (`,`)
- Configurable seek intervals (short and long seek with arrow keys)
- Playback resume with smart thresholds (remembers position per file; requires 3min+ duration, 5-95% position, 1min absolute minimum)
- **yt-dlp integration** for YouTube and web URL playback (Open URL dialog resolves via yt-dlp)
- Jump to specific time dialog (supports `h:mm:ss`, `m:ss`, and raw seconds)

### Audio & Video Tracks
- **Dynamic audio/video/subtitle track switching** from menu bar or right-click context menu
- TrackMenuDelegate dynamically queries the active engine (AVPlayer or VLC) when the menu opens
- **8 EQ presets** via libvlc equalizer (Flat, Bass Boost, Treble Boost, Vocal, Rock, Jazz, Classical, Electronic)
- **Audio delay adjustment** (pull/push/revert, applied to VLC engine in real-time via `libvlc_audio_set_delay`)
- Audio passthrough detection for AC3/E-AC3 over HDMI (AudioPassthroughManager + CoreAudio)
- **Real-time output device selection** (dynamically enumerates CoreAudio devices, filters virtual/aggregate devices)
- **Video brightness/contrast/saturation/hue/gamma adjustments** (Video Equalizer floating panel with sliders and reset)
- **Deinterlace modes** (Off, Blend, Bob, Linear, Yadif) via libvlc
- **Crop presets** (Default, 16:9, 4:3, 16:10, 1.85:1, 2.35:1) via libvlc crop geometry
- Extended volume support (>100% via VLC engine)
- Aspect ratio presets (Default, 4:3, 16:9, 16:10, 2.35:1, 2.39:1)
- Video rotation (left/right) and flip (horizontal/vertical) with revert

### Subtitles
- **SRT, ASS/SSA, WebVTT** external subtitle loading
- **ASS styled rendering** — parses V4+ Styles section to produce NSAttributedString with correct font, color, bold/italic
- ASS color parsing (&HAABBGGRR format) and override tag stripping
- **Embedded subtitle extraction** via FFmpeg (`FFmpegBridge.extractSubtitleTrack()` for text formats)
- **VLC native subtitle track rendering** (including PGS/VobSub bitmap subtitles)
- Subtitle delay sync (pull/push/revert with configurable step size)
- Subtitle visibility toggle (Ctrl+V)
- Configurable subtitle position (Bottom of Video, Bottom of Screen, Letterbox)
- Auto-load matching subtitle files from same directory
- Configurable font, font size, color, and outline via Preferences

### Casting
- **AirPlay** — Bonjour discovery of `_airplay._tcp` devices, native AVPlayer external playback, Screen Mirroring guidance
- **Chromecast** — Cast V2 protocol over TLS with `_googlecast._tcp` Bonjour discovery, friendly name extraction from TXT record `fn` key
- **DLNA/UPnP** — SSDP discovery + AVTransport SOAP control
- **Play on External Display** — move window to any connected screen in fullscreen
- Built-in HTTP server for streaming local files to cast devices

### UI (Movist Pro Style)
- Borderless window with transparent title bar (`fullSizeContentView` style)
- Auto-hiding controls with configurable timeout (auto-hide on mouse idle/exit)
- **Right-click context menu** with tracks, speed, screenshot, fullscreen, PiP
- **Codec badges in title bar** (DV, HDR, Atmos, codec name — e.g., H.264, HEVC, VP9, AV1)
- **On-screen display (OSD)** for all actions (seek, volume, speed, track changes, etc.)
- Seek bar with time tooltip on hover
- **Playlist sidebar panel** (Cmd+Shift+P) with double-click to play, current track highlighting
- **Media Inspector window** (Cmd+I) showing codec info, resolution, duration, audio/subtitle tracks via FFmpeg probing
- **Video Equalizer panel** with brightness/contrast/saturation/hue/gamma sliders and reset button
- **9-tab Preferences** with animated tab switching (General, Media Open, Playback, Playlist, Video, Audio, Subtitle, Full Screen, Keyboard/Mouse)
- Drag-and-drop file opening (anywhere in window via DragDropView)
- **Open Recent** with file history (custom UserDefaults-based RecentDocumentsMenuDelegate, up to 10 files)
- Pinch-to-fullscreen gesture (configurable action)
- Video window sizing (Half, Actual, Double, Fit to Screen, Fill Screen)
- Keep on Top / Always on Top (pin button in title bar + Window menu)
- Picture-in-Picture (PiP) support
- Welcome view shown when no file is loaded
- Theme support (System, Dark, Light) applied via NSAppearance

### System Integration
- **Now Playing / Control Center** integration (MPRemoteCommandCenter — play, pause, skip, seek, scrub)
- **Media key handling** (play/pause/next/prev from keyboard media keys, configurable)
- Open files from Finder (`application(_:openFile:)` and `application(_:openFiles:)`)
- **Screenshot capture** (PNG/JPEG/TIFF format, save to Desktop/Pictures/Downloads/Custom path)
- Quit-on-last-window-closed preference
- Window position restoration preference
- Services menu integration

## Requirements

- macOS 14.0 or later
- Apple Silicon or Intel Mac

## Build & Run

```bash
git clone https://github.com/zhaomin1995/video_player.git
cd video_player
open "Awesome Player.xcodeproj"
# Press Cmd+R to build and run
```

**No external dependencies needed** — FFmpeg and libvlc libraries are bundled in the repo. A build phase script automatically copies all dylibs and plugins into the app bundle.

## Architecture

```
File Input --> Format Check
                +-- MP4/MOV? --> AVPlayer (Dolby Vision + AirPlay + PiP)
                +-- MKV/AVI/WebM/other? --> libvlc (VLC engine, instant playback)

Both engines share:
  +-- SubtitleManager (external SRT/ASS/VTT overlay)
  +-- ABLoopController (A-B repeat)
  +-- NowPlayingController (MPRemoteCommandCenter)
  +-- ResumeManager (position persistence)
  +-- PlaylistManager (multi-file management)
  +-- OSDView (on-screen display)
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI Framework | AppKit (programmatic, no storyboards) |
| Native Playback | AVFoundation / AVPlayer |
| Universal Playback | libvlc (VLC 3.0) |
| Hardware Decoding | VideoToolbox (via AVPlayer and libvlc) |
| HDR Rendering | AVPlayerLayer with EDR |
| Media Probing | FFmpeg 7.1.1 (libavformat) |
| Remuxing Fallback | FFmpeg (libavcodec + libswresample) |
| Media Inspector | FFmpegBridge (libavformat probing + track enumeration) |
| EQ / Video Adjust | libvlc audio_equalizer + video_adjust APIs |
| Now Playing | MediaPlayer.framework (MPRemoteCommandCenter + MPNowPlayingInfoCenter) |
| Chromecast | Cast V2 protobuf over TLS |
| DLNA | SSDP + UPnP SOAP (AVTransport) |
| Audio Devices | CoreAudio (AudioObjectPropertyAddress) |
| URL Resolution | yt-dlp (optional, for YouTube/web URLs) |

## License

All rights reserved.
