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
- **yt-dlp integration** for YouTube and web URL playback — bundled self-contained binary (no install needed), resolution picker dialog with all available qualities (up to 4K/8K), high-res playback via VLC with separate video+audio stream merging
- Jump to specific time dialog (supports `h:mm:ss`, `m:ss`, and raw seconds)

### Audio & Video Tracks
- **Dynamic audio/video/subtitle track switching** from menu bar or right-click context menu
- TrackMenuDelegate dynamically queries the active engine (AVPlayer or VLC) when the menu opens
- **23 audio EQ presets** matching Movist Pro's set (Flat, Acoustic, Bass Booster, Bass Reducer, Classical, Dance, Deep, Electronic, Hip-Hop, Jazz, Latin, Loudness, Lounge, Perfect :), Piano, Pop, R&B, Rock, Small Speakers, Spoken Word, Treble Booster, Treble Reducer, Vocal Booster). Each preset is a 10-band ISO-frequency custom EQ built via `libvlc_audio_equalizer_new` + `set_amp_at_index`
- **VLC-style inline playback-speed slider** in the Playback menu (log2 scale, 0.25× to 4× with 1.0× centered), backed by Speed Presets submenu for click-to-set
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
- **16-color HTML/CSS palette** for both text color and background color (Black, Gray, Silver, White, Maroon, Red, Fuchsia, Yellow, Olive, Green, Teal, Lime, Purple, Navy, Blue, Aqua) — menu items show color swatches alongside names
- **Outline thickness** submenu (None, 1–6 px) — rendered via `NSAttributedString.strokeWidth` (negative for fill + stroke)
- **Background opacity** inline slider (0–100%) in the Subtitle menu, paired with the 16-color Background Color picker
- All subtitle styling preferences are KVO-observed so changes apply to the currently-displayed subtitle without needing to scrub
- Subtitle delay sync (pull/push/revert with configurable step size)
- Subtitle visibility toggle (Ctrl+V)
- Configurable subtitle position (Bottom of Video, Bottom of Screen, Letterbox)
- Auto-load matching subtitle files from same directory; falls back to embedded text-subtitle extraction for AVPlayer-based paths
- Configurable font, font size, color, and outline via Preferences

### Casting
- **AirPlay** — Bonjour discovery of `_airplay._tcp` devices, native AVPlayer external playback, Screen Mirroring guidance
- **Chromecast** — Cast V2 protocol over TLS with `_googlecast._tcp` Bonjour discovery, friendly name extraction from TXT record `fn` key
- **DLNA/UPnP** — SSDP discovery + AVTransport SOAP control
- **Play on External Display** — move window to any connected screen in fullscreen
- Built-in HTTP server for streaming local files to cast devices

### Convert / Stream
- **File → Convert / Stream…** (⇧⌘S) — VLC's Convert/Stream equivalent
- Drag-and-drop or browse to pick a source file; full path shown with middle-truncation if long (tooltip reveals the full path)
- **12 transcode profiles** matching VLC's built-in set:
  - Video — H.264 + MP3 (MP4 / TS)
  - Video — VP80 + Vorbis (WebM)
  - Video — Theora + Vorbis / Flac (OGG)
  - Video — MPEG-2 + MPGA (TS)
  - Video — WMV + WMA (ASF), DIV3 + MP3 (ASF)
  - Audio — Vorbis (OGG), MP3, MP3 (MP4), FLAC
- Conversion runs through libvlc's sout (stream output) pipeline (`#transcode{vcodec=X,acodec=Y,...}:standard{access=file,mux=Z,dst=PATH}`), reusing the shared libvlc instance so no extra plugin scan cost
- **Live CPU and GPU usage** displayed under the progress bar — CPU via `task_threads()` + `thread_info(THREAD_BASIC_INFO)`, GPU via IORegistry `IOAccelerator` `PerformanceStatistics["Device Utilization %"]` (Activity Monitor's GPU History uses the same key)
- ETA and percentage updated every 500ms alongside the progress bar
- Reveal-in-Finder button on completion

### Internationalization (11 languages)
- **Full UI localization** in 11 locales: English, Simplified Chinese (简体中文), Traditional Chinese (繁體中文), Cantonese (廣東話), Japanese (日本語), Korean (한국어), Spanish (Español), French (Français), German (Deutsch), Brazilian Portuguese (Português brasileiro), Russian (Русский)
- Translations stored in a single Xcode 15 `Localizable.xcstrings` catalog — 250+ keys × 10 non-English locales hand-translated, then QA'd by per-language native-reviewer LLM passes (which caught a real bug — Chinese had "Seek Forward 5s" / "Seek Backward 5s" swapped before shipping)
- **In-app language picker** in General preferences, listed by endonym (so users can find their language regardless of current UI state)
- **Live language switch — no relaunch.** Picking a language flips the menu bar, the Preferences window (rebuilt in place), and all future dialogs / OSD messages instantly. The chosen language also writes the standard macOS `AppleLanguages` key so it persists across launches and propagates to system dialogs at next launch
- Proper nouns (AirPlay, Chromecast, DLNA, Dolby Vision, HDR, MP4, FFmpeg, VLC, etc.) kept untranslated in every locale

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
- **9-tab Preferences** with animated tab switching (General, Open, Playback, Video, Audio, Subtitle, Screen, Input, Cast) — General tab now includes the in-app Language picker
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

**No external dependencies needed** — FFmpeg, libvlc, and yt-dlp are all bundled in the repo. A build phase script automatically copies all dylibs, plugins, and the yt-dlp distribution into the app bundle.

## Architecture

```
File Input --> Format Check
                +-- MP4/MOV? --> AVPlayer (Dolby Vision + AirPlay + PiP)
                +-- MKV/AVI/WebM/other? --> libvlc (VLC engine, instant playback)
                +-- HTTP(S) stream (no ext)? --> AVPlayer (streaming)

YouTube/Web URL --> yt-dlp (bundled) --> Resolution Picker
                +-- Merged format? --> AVPlayer
                +-- Video-only + Audio? --> libvlc (input-slave merge)

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
| URL Resolution | yt-dlp (bundled, self-contained with Python 3.14 runtime) |

## License

All rights reserved.
