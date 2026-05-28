import Cocoa
import AVFoundation

class SeekSliderView: NSView {
    var onSeek: ((Double) -> Void)?
    var duration: Double = 0

    private var progress: Double = 0
    private var isDragging = false
    private var dragProgress: Double = 0
    private var seekSuppressUntil: Date = .distantPast
    private var lastSoughtFraction: Double = -1
    private var lastScrubTime: Date = .distantPast
    private var didScrubOnMouseDown = false

    private let trackHeight: CGFloat = 4
    private let knobSize: CGFloat = 12
    private let expandedTrackHeight: CGFloat = 6
    private var isHovered = false

    private var trackingArea: NSTrackingArea?

    // Tooltip — added directly to the window's contentView to avoid clipping
    private var tooltipWindow: NSPanel?
    private var tooltipLabel: NSTextField?

    // Thumbnail filmstrip preview — 5 thumbnails (center = cursor, ±1, ±2 at
    // fixed time offsets). The center frame is rendered slightly larger and
    // bordered so it reads as "this is the moment you'll seek to". Edge frames
    // give scene context. Replaced the single hover-thumb with this strip in
    // the trackpad-gestures / seek-bar polish pass.
    private static let stripThumbWidth: CGFloat = 110
    private static let stripThumbHeight: CGFloat = 62
    private static let stripCenterScale: CGFloat = 1.25  // center thumb pops
    private static let stripPadding: CGFloat = 4
    private static let stripOffsetsSeconds: [Double] = [-20, -10, 0, 10, 20]

    private var thumbnailWindow: NSPanel?
    private var thumbnailViews: [NSImageView] = []
    private var thumbnailBgs: [NSView] = []
    private var imageGenerator: AVAssetImageGenerator?
    /// LRU thumbnail cache with byte-cost ceiling instead of a hard count
    /// ceiling. Earlier code wiped the whole dict at 150 entries — long
    /// films re-generated thumbs constantly on repeat scrubs. NSCache
    /// evicts the least-recently-used entries automatically when the
    /// cost limit is hit and survives memory pressure events.
    private lazy var thumbnailCache: NSCache<NSNumber, NSImage> = {
        let c = NSCache<NSNumber, NSImage>()
        c.totalCostLimit = 24 * 1024 * 1024  // ~24 MB of thumbnails
        return c
    }()
    private var pendingThumbnailTime: Double?

    var currentAsset: AVAsset? {
        didSet {
            // Cancel any in-flight thumbnail jobs against the prior asset
            // BEFORE clearing the cache or swapping the generator. Without
            // this, a job submitted against the old asset can complete after
            // the new asset is set and write its result into the (now-fresh)
            // cache with a key valid against the new asset's time domain —
            // showing a stale thumbnail for one tooltip cycle.
            imageGenerator?.cancelAllCGImageGeneration()
            pendingThumbnailTime = nil
            thumbnailCache.removeAllObjects()
            // Tear down the filmstrip panel — slot count is constant, but the
            // image views still hold references to the previous asset's NSImages
            // and rebuilding them lazily on next hover is cheap.
            thumbnailWindow?.orderOut(nil)
            thumbnailWindow = nil
            thumbnailViews.removeAll()
            thumbnailBgs.removeAll()
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
        let fraction = fractionForX(location.x)
        let time = fraction * duration
        showTooltip(at: event.locationInWindow, time: time)
        requestThumbnail(at: time, screenPoint: event.locationInWindow)
    }

    private func fractionForX(_ localX: CGFloat) -> Double {
        let trackX = knobSize / 2
        let trackWidth = bounds.width - knobSize
        return max(0, min(1, Double((localX - trackX) / trackWidth)))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let currentTrackHeight = isHovered || isDragging ? expandedTrackHeight : trackHeight
        let trackY = (bounds.height - currentTrackHeight) / 2
        let trackWidth = bounds.width - knobSize
        let trackX = knobSize / 2

        let trackRect = NSRect(x: trackX, y: trackY, width: trackWidth, height: currentTrackHeight)
        context.setFillColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        let bgPath = NSBezierPath(roundedRect: trackRect, xRadius: currentTrackHeight / 2, yRadius: currentTrackHeight / 2)
        bgPath.fill()

        let currentProgress = isDragging ? dragProgress : progress
        let fillWidth = trackWidth * currentProgress
        if fillWidth > 0 {
            let fillRect = NSRect(x: trackX, y: trackY, width: fillWidth, height: currentTrackHeight)
            context.setFillColor(NSColor.systemBlue.cgColor)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: currentTrackHeight / 2, yRadius: currentTrackHeight / 2)
            fillPath.fill()
        }

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
        didScrubOnMouseDown = false
        updateDragProgress(with: event)
        needsDisplay = true
        scrubSeek()
        didScrubOnMouseDown = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateDragProgress(with: event)
        needsDisplay = true

        if duration > 0 {
            let time = dragProgress * duration
            showTooltip(at: event.locationInWindow, time: time)
            requestThumbnail(at: time, screenPoint: event.locationInWindow)
        }
        // Live scrubbing — seek during drag, throttled to every 100ms
        let now = Date()
        if now.timeIntervalSince(lastScrubTime) >= 0.1 {
            scrubSeek()
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        updateDragProgress(with: event)
        progress = dragProgress

        if !didScrubOnMouseDown || abs(dragProgress - lastSoughtFraction) > 0.001 {
            lastSoughtFraction = progress
            seekSuppressUntil = Date().addingTimeInterval(0.2)
            onSeek?(progress)
        } else {
            seekSuppressUntil = Date().addingTimeInterval(0.2)
        }

        didScrubOnMouseDown = false
        hideThumbnail()
        needsDisplay = true
    }

    private func scrubSeek() {
        lastScrubTime = Date()
        lastSoughtFraction = dragProgress
        seekSuppressUntil = Date().addingTimeInterval(0.2)
        onSeek?(dragProgress)
    }

    private func updateDragProgress(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        dragProgress = fractionForX(location.x)
    }

    func setProgress(_ value: Double) {
        guard !isDragging else { return }
        if Date() < seekSuppressUntil {
            if lastSoughtFraction >= 0 && abs(value - lastSoughtFraction) < 0.05 {
                seekSuppressUntil = .distantPast
                lastSoughtFraction = -1
            } else {
                return
            }
        }
        progress = max(0, min(1, value))
        needsDisplay = true
    }

    // MARK: - Tooltip (floating panel to avoid clipping)

    private func showTooltip(at windowPoint: NSPoint, time: Double) {
        guard let parentWindow = window else { return }

        if tooltipWindow == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 80, height: 24),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = false
            panel.ignoresMouseEvents = true

            let bg = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 28))
            bg.wantsLayer = true
            bg.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.9).cgColor
            bg.layer?.cornerRadius = 5

            let label = NSTextField(labelWithString: "")
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            bg.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -4),
            ])

            panel.contentView = bg
            tooltipLabel = label
            tooltipWindow = panel
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        guard let tip = tooltipWindow, let label = tooltipLabel else { return }

        let total = Int(time)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        label.stringValue = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)

        let tipWidth: CGFloat = h > 0 ? 80 : 60
        let screenPoint = parentWindow.convertPoint(toScreen: NSPoint(x: windowPoint.x, y: windowPoint.y))

        let sliderScreenY = parentWindow.convertPoint(toScreen: convert(NSPoint(x: 0, y: bounds.maxY), to: nil)).y

        // Lift the time tooltip above the filmstrip when it's visible. Strip
        // height = centerThumbHeight * scale + 2*padding ≈ 86pt; +8 spacer.
        let thumbnailOffset: CGFloat = (thumbnailWindow?.isVisible == true)
            ? Self.stripThumbHeight * Self.stripCenterScale + Self.stripPadding * 2 + 8
            : 0
        let tipX = screenPoint.x - tipWidth / 2
        let tipY = sliderScreenY + 8 + thumbnailOffset

        tip.setFrame(NSRect(x: tipX, y: tipY, width: tipWidth, height: 28), display: true)
        tip.contentView?.frame = NSRect(x: 0, y: 0, width: tipWidth, height: 28)
        tip.orderFront(nil)
    }

    private func hideTooltip() {
        tooltipWindow?.orderOut(nil)
    }

    // MARK: - Thumbnail Filmstrip (floating panel)

    /// 2-second cache buckets — adjacent strip slots that fall in the same
    /// bucket reuse the same NSImage. With 10s offsets between strip thumbs
    /// every slot has its own bucket; for videos under ~40s the offsets get
    /// clamped to duration and the buckets start overlapping (fine — we just
    /// show the same thumb twice).
    private func cacheKey(for time: Double) -> NSNumber {
        return NSNumber(value: Int(time / 2))
    }

    private func requestThumbnail(at time: Double, screenPoint: NSPoint) {
        guard imageGenerator != nil, duration > 0 else { return }

        ensureStripPanel(at: screenPoint)
        layoutStrip(at: screenPoint, centerTime: time)

        // Slot times = center ± offsets, clamped to [0, duration]
        let slotTimes = Self.stripOffsetsSeconds.map { offset in
            max(0, min(duration, time + offset))
        }
        pendingThumbnailTime = time

        // Fill slots that already have a cached thumb immediately. Issue async
        // generation for the rest; when each finishes we update its slot only
        // if the user is still hovering in the same neighborhood.
        var needGen: [(slot: Int, time: Double)] = []
        for (i, slotTime) in slotTimes.enumerated() {
            if let cached = thumbnailCache.object(forKey: cacheKey(for: slotTime)) {
                thumbnailViews[i].image = cached
            } else {
                thumbnailViews[i].image = nil
                needGen.append((i, slotTime))
            }
        }

        guard let gen = imageGenerator, !needGen.isEmpty else { return }
        gen.cancelAllCGImageGeneration()
        let times = needGen.map { NSValue(time: CMTimeMakeWithSeconds($0.time, preferredTimescale: 600)) }
        // Map back from CMTime to (slot, originalTime) since AVAsset can return
        // requests in arbitrary order
        let timesBySlot = Dictionary(uniqueKeysWithValues: needGen.map { (CMTimeMakeWithSeconds($0.time, preferredTimescale: 600).seconds, $0) })

        gen.generateCGImagesAsynchronously(forTimes: times) { [weak self] requestedTime, cgImage, _, _, _ in
            guard let self = self, let cgImage = cgImage else { return }
            let reqSeconds = requestedTime.seconds
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            DispatchQueue.main.async {
                guard let info = timesBySlot.first(where: { abs($0.key - reqSeconds) < 0.5 })?.value else { return }
                let cost = Int(cgImage.width * cgImage.height * 4)
                self.thumbnailCache.setObject(image, forKey: self.cacheKey(for: info.time), cost: cost)
                // Drop stale results — user may have moved cursor far away
                if let pending = self.pendingThumbnailTime,
                   abs(pending - time) < Self.stripOffsetsSeconds.last! * 2,
                   info.slot < self.thumbnailViews.count {
                    self.thumbnailViews[info.slot].image = image
                }
            }
        }
    }

    private func ensureStripPanel(at screenPoint: NSPoint) {
        guard thumbnailWindow == nil, let parentWindow = window else { return }
        let count = Self.stripOffsetsSeconds.count
        let stripWidth = CGFloat(count) * Self.stripThumbWidth
            + CGFloat(count - 1) * Self.stripPadding
            + Self.stripThumbWidth * (Self.stripCenterScale - 1)  // extra room for the larger center thumb
        let stripHeight = Self.stripThumbHeight * Self.stripCenterScale + Self.stripPadding * 2

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: stripWidth, height: stripHeight),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: stripWidth, height: stripHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.05, alpha: 0.9).cgColor
        container.layer?.cornerRadius = 6

        thumbnailBgs.removeAll()
        thumbnailViews.removeAll()
        for i in 0..<count {
            let bg = NSView(frame: .zero)
            bg.wantsLayer = true
            bg.layer?.backgroundColor = NSColor.black.cgColor
            bg.layer?.cornerRadius = 3
            container.addSubview(bg)
            let imageView = NSImageView(frame: .zero)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.autoresizingMask = [.width, .height]
            bg.addSubview(imageView)
            // Highlight the center slot so users know which frame the click
            // will land on. Border width on the layer is on/off here.
            let isCenter = i == count / 2
            bg.layer?.borderColor = isCenter
                ? NSColor.systemBlue.cgColor
                : NSColor.white.withAlphaComponent(0.15).cgColor
            bg.layer?.borderWidth = isCenter ? 2 : 1
            thumbnailBgs.append(bg)
            thumbnailViews.append(imageView)
        }

        panel.contentView = container
        thumbnailWindow = panel
        parentWindow.addChildWindow(panel, ordered: .above)
    }

    private func layoutStrip(at screenPoint: NSPoint, centerTime: Double) {
        guard let panel = thumbnailWindow, let parentWindow = window else { return }
        let count = Self.stripOffsetsSeconds.count
        let centerW = Self.stripThumbWidth * Self.stripCenterScale
        let centerH = Self.stripThumbHeight * Self.stripCenterScale
        let edgeW = Self.stripThumbWidth
        let edgeH = Self.stripThumbHeight
        let pad = Self.stripPadding

        let stripWidth = CGFloat(count - 1) * (edgeW + pad) + centerW + pad * 2
        let stripHeight = centerH + pad * 2

        var x: CGFloat = pad
        for (i, bg) in thumbnailBgs.enumerated() {
            let isCenter = i == count / 2
            let w = isCenter ? centerW : edgeW
            let h = isCenter ? centerH : edgeH
            let y = (stripHeight - h) / 2
            bg.frame = NSRect(x: x, y: y, width: w, height: h)
            // Image view fills the bg with a 2pt inset so the border shows.
            if let iv = bg.subviews.first as? NSImageView {
                iv.frame = NSRect(x: 2, y: 2, width: w - 4, height: h - 4)
            }
            x += w + pad
        }

        let sliderScreenY = parentWindow.convertPoint(toScreen: convert(NSPoint(x: 0, y: bounds.maxY), to: nil)).y
        let scrPt = parentWindow.convertPoint(toScreen: screenPoint)
        // Center the strip's center thumb on the cursor X. Then clamp X so the
        // strip doesn't run off the screen edge.
        var stripX = scrPt.x - stripWidth / 2
        if let screen = parentWindow.screen {
            let vf = screen.visibleFrame
            stripX = max(vf.minX + 4, min(vf.maxX - stripWidth - 4, stripX))
        }
        let stripY = sliderScreenY + 8

        panel.setFrame(NSRect(x: stripX, y: stripY, width: stripWidth, height: stripHeight), display: true)
        panel.contentView?.frame = NSRect(x: 0, y: 0, width: stripWidth, height: stripHeight)
        panel.orderFront(nil)
    }

    private func hideThumbnail() {
        thumbnailWindow?.orderOut(nil)
        pendingThumbnailTime = nil
    }
}
