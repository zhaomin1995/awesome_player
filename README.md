# Awesome Player

A full-featured macOS video player that combines **Dolby Vision** playback with **VLC-quality codec support** — instant MKV playback, AirPlay streaming, Chromecast casting, and a polished Movist Pro-style UI.

## Features

### Playback
- **Instant MKV/AVI/WebM playback** via integrated libvlc — no remuxing, no delay
- **Dolby Vision / HDR10 / HLG** for native MP4/MOV via AVPlayer + VideoToolbox
- **30+ container formats** and all codecs VLC supports (H.264, HEVC, VP9, AV1, etc.)
- Keyboard shortcuts: Space (play/pause), arrows (seek/volume), M (mute), F (fullscreen)
- A-B loop, playback speed (0.25x–4x), configurable seek intervals

### Casting
- **AirPlay** — native via AVPlayer with external display fallback
- **Chromecast** — Cast V2 protocol over TLS with device discovery
- **DLNA/UPnP** — SSDP discovery + AVTransport control
- **Play on External Display** — move to any connected screen in fullscreen

### Audio
- 10-band EQ with 8 presets (Flat, Bass Boost, Rock, Jazz, etc.)
- Audio passthrough detection for AC3/E-AC3 over HDMI
- Real-time output device selection (filters virtual devices)

### UI (Movist Pro Style)
- Borderless window with transparent title bar
- Auto-hiding controls (1s idle or mouse exit)
- 9-tab preferences with animated tab switching
- Seek OSD with timestamp and percentage
- DV/HDR/Atmos codec badges in title bar
- All menu items functional with stateful checkmarks

## Requirements

- macOS 14.0 or later
- Apple Silicon or Intel Mac

## Build & Run

```bash
git clone https://github.com/zhaomin1995/video_player.git
cd video_player
open "Awesome Player.xcodeproj"
# Press ⌘R to build and run
```

**No external dependencies needed** — FFmpeg and libvlc libraries are bundled in the repo. A build phase script automatically copies all dylibs and plugins into the app bundle.

## Architecture

```
File Input → Format Check
               ├── MP4/MOV? → AVPlayer (Dolby Vision + AirPlay)
               └── MKV/AVI/WebM? → libvlc (VLC engine, instant playback)
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
| Chromecast | Cast V2 protobuf over TLS |
| DLNA | SSDP + UPnP SOAP |

## License

All rights reserved.
