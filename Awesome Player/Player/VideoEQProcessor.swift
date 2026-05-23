import AVFoundation
import CoreImage

class VideoEQProcessor {
    var brightness: Float = 0 { didSet { updateNeeded = true } }
    var contrast: Float = 1 { didSet { updateNeeded = true } }
    var saturation: Float = 1 { didSet { updateNeeded = true } }
    var sharpness: Float = 0 { didSet { updateNeeded = true } }
    var gamma: Float = 1 { didSet { updateNeeded = true } }

    private var updateNeeded = false
    private(set) var isActive = false

    var hasAdjustments: Bool {
        brightness != 0 || contrast != 1 || saturation != 1 || sharpness != 0 || gamma != 1
    }

    func createVideoComposition(for asset: AVAsset) -> AVVideoComposition? {
        guard hasAdjustments else { return nil }

        let composition = AVVideoComposition(asset: asset) { [weak self] request in
            guard let self = self else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }

            var image = request.sourceImage

            // Color controls: brightness, contrast, saturation
            if self.brightness != 0 || self.contrast != 1 || self.saturation != 1 {
                let colorFilter = CIFilter(name: "CIColorControls")!
                colorFilter.setValue(image, forKey: kCIInputImageKey)
                colorFilter.setValue(self.brightness, forKey: kCIInputBrightnessKey)
                colorFilter.setValue(self.contrast, forKey: kCIInputContrastKey)
                colorFilter.setValue(self.saturation, forKey: kCIInputSaturationKey)
                if let output = colorFilter.outputImage {
                    image = output
                }
            }

            // Sharpness
            if self.sharpness > 0 {
                let sharpenFilter = CIFilter(name: "CISharpenLuminance")!
                sharpenFilter.setValue(image, forKey: kCIInputImageKey)
                sharpenFilter.setValue(self.sharpness, forKey: kCIInputSharpnessKey)
                if let output = sharpenFilter.outputImage {
                    image = output
                }
            }

            // Gamma
            if self.gamma != 1 {
                let gammaFilter = CIFilter(name: "CIGammaAdjust")!
                gammaFilter.setValue(image, forKey: kCIInputImageKey)
                gammaFilter.setValue(self.gamma, forKey: "inputPower")
                if let output = gammaFilter.outputImage {
                    image = output
                }
            }

            request.finish(with: image, context: nil)
        }

        isActive = true
        return composition
    }

    func reset() {
        brightness = 0
        contrast = 1
        saturation = 1
        sharpness = 0
        gamma = 1
        isActive = false
    }

    func applyToPlayerItem(_ item: AVPlayerItem) {
        if hasAdjustments {
            item.videoComposition = createVideoComposition(for: item.asset)
        } else {
            item.videoComposition = nil
            isActive = false
        }
    }
}
