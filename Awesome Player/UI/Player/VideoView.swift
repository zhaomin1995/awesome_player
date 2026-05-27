import Cocoa
import AVFoundation

class VideoView: NSView {
    private var playerLayer: AVPlayerLayer?
    var onFileDropped: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first else { return false }
        onFileDropped?(url)
        return true
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
        // Disable implicit animations on size/position changes. During
        // NSWindow.toggleFullScreen, the layer would otherwise animate its
        // bounds in parallel with the window animation — AVPlayer's render
        // pipeline gets confused by the moving target and stalls for ~1-2s.
        // NSNull tells CoreAnimation "do not animate this property".
        layer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "sublayers": NSNull(),
            "contents": NSNull(),
        ]

        if let contentLayer = self.layer {
            layer.contentsScale = contentLayer.contentsScale
            contentLayer.addSublayer(layer)
            applyHDRToneMapping(to: layer)
        }

        playerLayer = layer
    }

    override func layout() {
        super.layout()
        // Wrap in a no-animation transaction so layout-driven frame changes
        // (especially during fullscreen transitions) don't trigger implicit
        // CoreAnimation transitions on the player layer's contents.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.sublayers?.forEach { $0.frame = bounds }
        CATransaction.commit()
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
        case 1: target?.wantsExtendedDynamicRangeContent = true
        case 2: target?.wantsExtendedDynamicRangeContent = false
        default: target?.wantsExtendedDynamicRangeContent = true
        }
    }
}
