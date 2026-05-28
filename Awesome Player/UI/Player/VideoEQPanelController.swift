import Cocoa

class VideoEQPanelController: NSWindowController {
    weak var playerViewController: PlayerViewController?
    /// Keep slider rows so a language flip can re-set the leading labels in
    /// place. Earlier code hardcoded English here and never refreshed.
    private var labelsByID: [String: NSTextField] = [:]
    private var resetButton: NSButton?

    init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 280),
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        window.title = L("Video Equalizer")
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        super.init(window: window)
        setupContent()
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange),
                                                name: .languageDidChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func handleLanguageChange() {
        window?.title = L("Video Equalizer")
        for (id, label) in labelsByID {
            label.stringValue = Self.localizedSliderLabel(for: id)
        }
        resetButton?.title = L("Reset")
    }

    private static func localizedSliderLabel(for id: String) -> String {
        switch id {
        case "brightness": return L("Brightness")
        case "contrast":   return L("Contrast")
        case "saturation": return L("Saturation")
        case "hue":        return L("Hue")
        case "gamma":      return L("Gamma")
        default:           return id.capitalized
        }
    }

    private func setupContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let params: [(String, Float, Float, Float)] = [
            ("brightness", 0, 2, 1),
            ("contrast",   0, 2, 1),
            ("saturation", 0, 3, 1),
            ("hue",        -180, 180, 0),
            ("gamma",      0.01, 10, 1),
        ]

        for (id, min, max, def) in params {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let lbl = NSTextField(labelWithString: Self.localizedSliderLabel(for: id))
            lbl.widthAnchor.constraint(equalToConstant: 80).isActive = true
            labelsByID[id] = lbl
            let slider = NSSlider(value: Double(def), minValue: Double(min), maxValue: Double(max), target: self, action: #selector(sliderChanged(_:)))
            slider.identifier = NSUserInterfaceItemIdentifier(id)
            slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let valLabel = NSTextField(labelWithString: String(format: "%.1f", def))
            valLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
            valLabel.tag = id.hashValue
            row.addArrangedSubview(lbl)
            row.addArrangedSubview(slider)
            row.addArrangedSubview(valLabel)
            stack.addArrangedSubview(row)
        }

        let resetBtn = NSButton(title: L("Reset"), target: self, action: #selector(resetAll))
        resetBtn.bezelStyle = .rounded
        self.resetButton = resetBtn
        stack.addArrangedSubview(resetBtn)

        window?.contentView = stack
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let id = sender.identifier?.rawValue,
              let vlc = playerViewController?.vlcEngine else { return }
        let value = Float(sender.doubleValue)
        switch id {
        case "brightness": vlc.setBrightness(value)
        case "contrast": vlc.setContrast(value)
        case "saturation": vlc.setSaturation(value)
        case "hue": vlc.setHue(value)
        case "gamma": vlc.setGamma(value)
        default: break
        }
        updateValueLabel(for: sender)
    }

    private func updateValueLabel(for slider: NSSlider) {
        guard let row = slider.superview as? NSStackView else { return }
        for sub in row.arrangedSubviews {
            if let label = sub as? NSTextField, label.tag == slider.identifier?.rawValue.hashValue ?? 0 {
                label.stringValue = String(format: "%.1f", slider.doubleValue)
                break
            }
        }
    }

    @objc private func resetAll() {
        guard let vlc = playerViewController?.vlcEngine else { return }
        vlc.setVideoAdjust(enabled: false)
        // Reset sliders to defaults
        if let stack = window?.contentView as? NSStackView {
            for row in stack.arrangedSubviews {
                guard let rowStack = row as? NSStackView else { continue }
                for sub in rowStack.arrangedSubviews {
                    if let slider = sub as? NSSlider {
                        switch slider.identifier?.rawValue {
                        case "brightness": slider.doubleValue = 1
                        case "contrast": slider.doubleValue = 1
                        case "saturation": slider.doubleValue = 1
                        case "hue": slider.doubleValue = 0
                        case "gamma": slider.doubleValue = 1
                        default: break
                        }
                        updateValueLabel(for: slider)
                    }
                }
            }
        }
        playerViewController?.showOSD(L("Video adjustments reset"))
    }
}
