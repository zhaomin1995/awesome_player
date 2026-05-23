# Awesome Player

A full-featured macOS video player that combines **Dolby Vision** playback with **AirPlay** streaming — something no existing player offers. Inspired by Movist Pro's polished UI and VLC's codec breadth.

## Features

### Playback
- **Dolby Vision / HDR10 / HLG** support via AVPlayer + VideoToolbox
- **MKV, AVI, MP4, MOV** and 30+ container formats via FFmpeg remuxing
- Automatic **Vorbis/DTS/WMA → AAC** audio transcoding for incompatible codecs
- Keyboard shortcuts: Space (play/pause), arrows (seek/volume), M (mute), F (fullscreen)
- A-B loop repeat, playback speed control (0.25x–4x)

### Casting
- **AirPlay** — native via AVPlayer (Dolby Vision streams to Apple TV)
- **Chromecast** — Bonjour discovery + Cast V2 protocol over TLS
- **DLNA/UPnP** — SSDP discovery + AVTransport SOAP control

### Audio
- 10-band parametric equalizer with 8 presets
- Dynamics compressor, spatializer/reverb, stereo widener
- Pitch shifter (semitone steps), loudness normalization
- Audio passthrough detection (AC3/E-AC3/DTS over HDMI)
- Real-time output device enumeration and selection

### Video
- CIFilter-based video EQ: brightness, contrast, saturation, hue, sharpness, gamma
- Rotate left/right, flip horizontal/vertical
- Aspect ratio presets, half/actual/double/fit-to-screen sizing

### Subtitles
- **Text**: SRT, ASS/SSA, WebVTT parsers
- **Bitmap**: PGS (Blu-ray), VobSub (DVD) via FFmpeg
- Auto-discovery of matching subtitle files
- Configurable delay, encoding, font, position

### UI (Movist Pro Style)
- Borderless window with transparent title bar and custom traffic lights
- Dark radial gradient welcome screen with centered play icon
- Auto-hiding control bar with dark vibrancy background
- 6 slide-up panels: Playlist, Audio, Subtitle, Video EQ, Media Info, Cast
- 11-tab preferences window
- OSD messages with fade animations
- DV/HDR/Atmos codec badges in title bar

## Requirements

- macOS 14.0 or later
- Apple Silicon or Intel Mac

## Build & Run

```bash
git clone https://github.com/zhaomin1995/awesome_player.git
cd awesome_player
open "Awesome Player.xcodeproj"
```

In Xcode, add a **Run Script** build phase to copy FFmpeg dylibs:
```bash
mkdir -p "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
for dylib in libavformat libavcodec libavutil libswresample libswscale; do
    SRC=$(find "${PROJECT_DIR}/Vendor/ffmpeg/lib" -name "${dylib}.*.*.*.dylib" -not -type l | head -1)
    [ -n "$SRC" ] && cp -f "$SRC" "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/"
done
```

Then press **⌘R** to build and run.

**No Homebrew or external dependencies needed** — FFmpeg libraries are bundled in the repo.

## Architecture

```
File Input → Codec Probe (FFmpeg) → Format Router
                                     ├── AVPlayer-compatible? → AVPlayer (DV + AirPlay)
                                     └── Not compatible? → FFmpeg Decoder (local only)

MKV with HEVC → remux to temp MP4 → AVPlayer (preserves DV metadata)
MKV with Vorbis audio → transcode to AAC (via AVAudioFifo) → AVPlayer
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI Framework | AppKit (programmatic, no storyboards) |
| Video Playback | AVFoundation / AVPlayer |
| Hardware Decoding | VideoToolbox |
| HDR Rendering | AVPlayerLayer with EDR |
| Container Demuxing | FFmpeg 7.1.1 (libavformat) |
| Audio Transcoding | FFmpeg (libavcodec + libswresample) |
| Audio Processing | AVAudioEngine (EQ, compressor, reverb, pitch) |
| Casting | Network.framework (NWConnection, NWListener) |
| Video Filters | CoreImage (CIFilter) |

## License

All rights reserved.
