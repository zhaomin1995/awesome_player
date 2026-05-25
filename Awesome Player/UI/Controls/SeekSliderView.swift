import Cocoa
import AVFoundation

class SeekSliderView: NSView {
    var onSeek: ((Double) -> Void)?
    var duration: Double = 0

    private var progress: Double = 0
    private var isDragging = false
    private var dragProgress: Double = 0

    private let trackHeight: CGFloat = 4
    private let knobSize: CGFloat = 12
    private let expandedTrackHeight: CGFloat = 6
    private var isHovered = false

    private var trackingArea: NSTrackingArea?
    private var tooltipView: NSView?
    private var tooltipLabel: NSTextField?

    // Thumbnail preview
    private var thumbnailView: NSImageView?
    private var thumbnailContainer: NSView?
    private var imageGenerator: AVAssetImageGenerator?
    private var thumbnailCache: [Int: NSImage] = [:]
    private var pendingThumbnailTime: Double?
    /// Set by PlayerViewController when a file opens
    var currentAsset: AVAsset? {
        didSet {
            thumbnailCache.removeAll()
            if let asset = currentAsset {
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 240, height: 135)
                gen.requestedTimeToleranceBefore = CMTimeMake(value: 1, timescale: 1)
                gen.requestedTimeToleranceAfter = CMTimeMake(value: 1, timescale: 1)
                imageGenerator = gen
            } else {
                imageGenerator = nil
            }
        }
    }

    /// For VLC path: use snapshot-based thumbnails
    var vlcEngine: VLCPlayerEngine?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        hideTooltip()
        hideThumbnail()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard duration > 0 else { return }
        let location = convert(event.locationInWindow, from: nil)
        let trackX = knobSize / 2
        let trackWidth = bounds.width - knobSize
        let fraction = max(0, min(1, Double((location.x - trackX) / trackWidth)))
        let time = fraction * duration
        showTooltip(at: location.x, time: time)
        requestThumbnail(at: time, xPosition: location.x)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let currentTrackHeight = isHovered || isDragging ? expandedTrackHeight : trackHeight
        let trackY = (bounds.height - currentTrackHeight) / 2
        let trackWidth = bounds.width - knobSize
        let trackX = knobSize / 2

        // Track background
        let trackRect = NSRect(x: trackX, y: trackY, width: trackWidth, height: currentTrackHeight)
        context.setFillColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        let bgPath = NSBezierPath(roundedRect: trackRect, xRadius: currentTrackHeight / 2, yRadius: currentTrackHeight / 2)
        bgPath.fill()

        // Progress fill
        let currentProgress = isDragging ? dragProgress : progress
        let fillWidth = trackWidth * currentProgress
        if fillWidth > 0 {
            let fillRect = NSRect(x: trackX, y: trackY, width: fillWidth, height: currentTrackHeight)
            context.setFillColor(NSColor.systemBlue.cgColor)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: currentTrackHeight / 2, yRadius: currentTrackHeight / 2)
            fillPath.fill()
        }

        // Knob
        if isHovered || isDragging {
            let knobX = trackX + fillWidth - knobSize / 2
            let knobY = (bounds.height - knobSize) / 2
            let knobRect = NSRect(x: knobX, y: knobY, width: knobSize, height: knobSize)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: knobRect)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateDragProgress(with: event)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateDragProgress(with: event)
        needsDisplay = true

        if duration > 0 {
            let location = convert(event.locationInWindow, from: nil)
            let time = dragProgress * duration
            showTooltip(at: location.x, time: time)
            requestThumbnail(at: time, xPosition: location.x)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        updateDragProgress(with: event)
        progress = dragProgress
        onSeek?(progress)
        hideThumbnail()
        needsDisplay = true
    }

    private func updateDragProgress(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let trackX = knobSize / 2
        let trackWidth = bounds.width - knobSize
        dragProgress = max(0, min(1, Double((location.x - trackX) / trackWidth)))
    }

    func setProgress(_ value: Double) {
        guard !isDragging else { return }
        progress = max(0, min(1, value))
        needsDisplay = true
    }

    // MARK: - Time Tooltip

    private func showTooltip(at x: CGFloat, time: Double) {
        if tooltipView == nil {
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 70, height: 24))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.9).cgColor
            container.layer?.cornerRadius = 4

            let label = NSTextField(labelWithString: "")
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            tooltipLabel = label
            tooltipView = container
            superview?.addSubview(container)
        }

        guard let tip = tooltipView, let label = tooltipLabel else { return }

        let total = Int(time)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        label.stringValue = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)

        let tipWidth: CGFloat = h > 0 ? 80 : 60
        let thumbnailHeight: CGFloat = (thumbnailContainer?.isHidden == false) ? 90 : 0
        let localPoint = NSPoint(x: x, y: bounds.maxY + 4 + thumbnailHeight)
        let superPoint = convert(localPoint, to: superview)
        tip.frame = NSRect(
            x: max(0, min(superPoint.x - tipWidth / 2, (superview?.bounds.width ?? 300) - tipWidth)),
            y: superPoint.y,
            width: tipWidth, height: 24
        )
        tip.isHidden = false
    }

    private func hideTooltip() {
        tooltipView?.isHidden = true
    }

    // MARK: - Thumbnail Preview

    private func requestThumbnail(at time: Double, xPosition: CGFloat) {
        guard imageGenerator != nil || vlcEngine != nil else { return }

        let cacheKey = Int(time / 2) // Cache at 2-second granularity

        if let cached = thumbnailCache[cacheKey] {
            showThumbnail(cached, at: xPosition)
            return
        }

        guard let gen = imageGenerator else { return }

        pendingThumbnailTime = time
        let cmTime = CMTimeMakeWithSeconds(time, preferredTimescale: 600)

        gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { [weak self] _, cgImage, _, _, _ in
            guard let self = self, let cgImage = cgImage else { return }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            DispatchQueue.main.async {
                self.thumbnailCache[cacheKey] = image
                if let pending = self.pendingThumbnailTime, abs(pending - time) < 3 {
                    self.showThumbnail(image, at: xPosition)
                }
            }
        }
    }

    private func showThumbnail(_ image: NSImage, at x: CGFloat) {
        let thumbWidth: CGFloat = 160
        let thumbHeight: CGFloat = 90

        if thumbnailContainer == nil {
            let container = NSView(frame: .zero)
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(white: 0.05, alpha: 0.95).cgColor
            container.layer?.cornerRadius = 6
            container.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            container.layer?.borderWidth = 1

            let imageView = NSImageView(frame: .zero)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 3),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -3),
            ])

            thumbnailView = imageView
            thumbnailContainer = container
            superview?.addSubview(container)
        }

        guard let container = thumbnailContainer, let imageView = thumbnailView else { return }

        imageView.image = image

        let localPoint = NSPoint(x: x, y: bounds.maxY + 4)
        let superPoint = convert(localPoint, to: superview)
        container.frame = NSRect(
            x: max(0, min(superPoint.x - thumbWidth / 2, (superview?.bounds.width ?? 300) - thumbWidth)),
            y: superPoint.y,
            width: thumbWidth, height: thumbHeight
        )
        container.isHidden = false
    }

    private func hideThumbnail() {
        thumbnailContainer?.isHidden = true
        pendingThumbnailTime = nil
    }
}
