import AVFoundation

struct AudioTrackInfo {
    let index: Int
    let language: String?
    let title: String?
    let codecName: String?
    let channelCount: Int
    let sampleRate: Double
    let isDefault: Bool

    var displayName: String {
        var parts: [String] = []
        if let title = title, !title.isEmpty {
            parts.append(title)
        }
        if let lang = language, !lang.isEmpty {
            parts.append("(\(lang))")
        }
        if let codec = codecName {
            parts.append("[\(codec)]")
        }
        parts.append("\(channelCount)ch")
        return parts.isEmpty ? "Track \(index + 1)" : parts.joined(separator: " ")
    }
}

class AudioTrackManager {
    private var playerItem: AVPlayerItem?
    private(set) var tracks: [AudioTrackInfo] = []
    private(set) var selectedIndex: Int = 0

    func loadTracks(from item: AVPlayerItem) async {
        playerItem = item
        tracks = []

        guard let asset = item.asset as? AVURLAsset else { return }
        guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio) else { return }

        for (index, track) in audioTracks.enumerated() {
            let formatDescs = try? await track.load(.formatDescriptions)
            let languageCode = try? await track.load(.languageCode)

            var codecName: String?
            var channelCount = 2
            var sampleRate = 48000.0

            if let desc = formatDescs?.first {
                let codecType = CMFormatDescriptionGetMediaSubType(desc)
                codecName = mapAudioCodec(codecType)

                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    channelCount = Int(asbd.pointee.mChannelsPerFrame)
                    sampleRate = asbd.pointee.mSampleRate
                }
            }

            let info = AudioTrackInfo(
                index: index,
                language: languageCode,
                title: nil,
                codecName: codecName,
                channelCount: channelCount,
                sampleRate: sampleRate,
                isDefault: index == 0
            )
            tracks.append(info)
        }
    }

    func selectTrack(at index: Int) {
        guard let item = playerItem, index < tracks.count else { return }
        selectedIndex = index

        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        if index < group.options.count {
            item.select(group.options[index], in: group)
        }
    }

    private func mapAudioCodec(_ type: FourCharCode) -> String {
        switch type {
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatAC3: return "AC3"
        case kAudioFormatEnhancedAC3: return "E-AC3"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatOpus: return "Opus"
        default: return "Audio"
        }
    }
}
