import AVFoundation

class AudioCompressor {
    let node: AVAudioUnitEffect

    private var threshold: Float = -20
    private var ratio: Float = 4
    private var attackTime: Float = 0.01
    private var releaseTime: Float = 0.1
    private var makeupGain: Float = 0

    init() {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        node = AVAudioUnitEffect(audioComponentDescription: description)
    }

    func setThreshold(_ value: Float) {
        threshold = max(-40, min(0, value))
        updateParameter(kDynamicsProcessorParam_Threshold, value: threshold)
    }

    func setRatio(_ value: Float) {
        ratio = max(1, min(20, value))
        updateParameter(kDynamicsProcessorParam_HeadRoom, value: 20.0 / ratio)
    }

    func setAttackTime(_ value: Float) {
        attackTime = max(0.001, min(0.2, value))
        updateParameter(kDynamicsProcessorParam_AttackTime, value: attackTime)
    }

    func setReleaseTime(_ value: Float) {
        releaseTime = max(0.01, min(3.0, value))
        updateParameter(kDynamicsProcessorParam_ReleaseTime, value: releaseTime)
    }

    func setMakeupGain(_ value: Float) {
        makeupGain = max(0, min(40, value))
        updateParameter(kDynamicsProcessorParam_OverallGain, value: makeupGain)
    }

    func setEnabled(_ enabled: Bool) {
        node.bypass = !enabled
    }

    private func updateParameter(_ paramID: AudioUnitParameterID, value: Float) {
        let audioUnit = node.audioUnit
        AudioUnitSetParameter(audioUnit, paramID, kAudioUnitScope_Global, 0, value, 0)
    }
}
