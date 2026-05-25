import Cocoa
import AVFoundation

class VideoView: NSView {
    private var playerLayer: AVPlayerLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    func setPlayer(_ player: AVPlayer?) {
        playerLayer?.removeFromSuperlayer()

        guard let player = player else {
            playerLayer = nil
            return
        }

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        if let contentLayer = self.layer {
            layer.contentsScale = contentLayer.contentsScale
            contentLayer.addSublayer(layer)
            applyHDRToneMapping(to: layer)
        }

        playerLayer = layer
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.forEach { $0.frame = bounds }
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        playerLayer?.videoGravity = gravity
    }

    func getPlayerLayer() -> AVPlayerLayer? {
        playerLayer
    }

    func setLayerTransform(_ transform: CATransform3D) {
        playerLayer?.transform = transform
    }

    func applyHDRToneMapping(to layer: AVPlayerLayer? = nil) {
        let target = layer ?? playerLayer
        let mode = UserDefaults.standard.integer(forKey: Defaults.hdrToneMappingMode)
        switch mode {
        case 1: // Always HDR — enable EDR
            target?.wantsExtendedDynamicRangeContent = true
        case 2: // Force SDR — disable EDR
            target?.wantsExtendedDynamicRangeContent = false
        default: // System — let macOS decide
            target?.wantsExtendedDynamicRangeContent = true
        }
    }
}
