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
            layer.wantsExtendedDynamicRangeContent = true
        }

        playerLayer = layer
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        playerLayer?.videoGravity = gravity
    }
}
