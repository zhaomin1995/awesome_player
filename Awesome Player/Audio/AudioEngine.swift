import AVFoundation
import Cocoa

class AudioEngine {
    private let engine = AVAudioEngine()
    private let equalizer: AudioEqualizer
    private let compressor: AudioCompressor
    private let spatializer: AudioSpatializer
    private let pitchShifter: AudioPitchShifter

    private(set) var isPassthroughActive = false

    init() {
        equalizer = AudioEqualizer()
        compressor = AudioCompressor()
        spatializer = AudioSpatializer()
        pitchShifter = AudioPitchShifter()
    }

    func setupPipeline() {
        engine.attach(equalizer.node)
        engine.attach(compressor.node)
        engine.attach(spatializer.node)
        engine.attach(pitchShifter.node)

        let mainMixer = engine.mainMixerNode

        engine.connect(equalizer.node, to: compressor.node, format: nil)
        engine.connect(compressor.node, to: spatializer.node, format: nil)
        engine.connect(spatializer.node, to: pitchShifter.node, format: nil)
        engine.connect(pitchShifter.node, to: mainMixer, format: nil)

        do {
            try engine.start()
        } catch {
            print("AudioEngine failed to start: \(error)")
        }
    }

    func stop() {
        engine.stop()
    }

    var inputNode: AVAudioNode {
        equalizer.node
    }

    func setPassthroughActive(_ active: Bool) {
        isPassthroughActive = active
        equalizer.setEnabled(!active)
        compressor.setEnabled(!active)
        spatializer.setEnabled(!active)
        pitchShifter.setEnabled(!active)
    }

    func getEqualizer() -> AudioEqualizer { equalizer }
    func getCompressor() -> AudioCompressor { compressor }
    func getSpatializer() -> AudioSpatializer { spatializer }
    func getPitchShifter() -> AudioPitchShifter { pitchShifter }
}
