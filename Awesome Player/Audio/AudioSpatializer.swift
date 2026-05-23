import AVFoundation

class AudioSpatializer {
    let node: AVAudioUnitReverb

    struct ReverbPreset {
        let name: String
        let avPreset: AVAudioUnitReverbPreset
    }

    static let presets: [ReverbPreset] = [
        ReverbPreset(name: "Off", avPreset: .cathedral),
        ReverbPreset(name: "Small Room", avPreset: .smallRoom),
        ReverbPreset(name: "Medium Room", avPreset: .mediumRoom),
        ReverbPreset(name: "Large Hall", avPreset: .largeHall),
        ReverbPreset(name: "Cathedral", avPreset: .cathedral),
        ReverbPreset(name: "Plate", avPreset: .plate),
    ]

    private var currentPresetIndex = 0

    var wetDryMix: Float {
        get { node.wetDryMix }
        set { node.wetDryMix = max(0, min(100, newValue)) }
    }

    init() {
        node = AVAudioUnitReverb()
        node.bypass = true
        node.wetDryMix = 30
    }

    func applyPreset(_ preset: ReverbPreset) {
        node.loadFactoryPreset(preset.avPreset)
        if preset.name == "Off" {
            node.bypass = true
        } else {
            node.bypass = false
        }
    }

    func applyPreset(at index: Int) {
        guard index < Self.presets.count else { return }
        currentPresetIndex = index
        applyPreset(Self.presets[index])
    }

    func setEnabled(_ enabled: Bool) {
        node.bypass = !enabled
    }
}
