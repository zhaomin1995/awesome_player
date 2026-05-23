import AVFoundation

class AudioPitchShifter {
    let node: AVAudioUnitTimePitch

    var pitch: Float {
        get { node.pitch / 100.0 }
        set { node.pitch = max(-2400, min(2400, newValue * 100.0)) }
    }

    var pitchInSemitones: Float {
        get { node.pitch / 100.0 }
        set { node.pitch = newValue * 100.0 }
    }

    init() {
        node = AVAudioUnitTimePitch()
        node.pitch = 0
        node.bypass = true
    }

    func setEnabled(_ enabled: Bool) {
        node.bypass = !enabled
    }

    func reset() {
        node.pitch = 0
    }
}
