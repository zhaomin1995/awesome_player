import Cocoa

class SubtitleOverlayView: NSView {
    /// HTML/CSS 16 named colors, matching VLC's subtitle color palette.
    /// Index in this array == value stored in UserDefaults — never reorder.
    static let namedColors: [(name: String, color: NSColor)] = [
        ("Black",   NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1)),
        ("Gray",    NSColor(srgbRed: 0.50, green: 0.50, blue: 0.50, alpha: 1)),
        ("Silver",  NSColor(srgbRed: 0.75, green: 0.75, blue: 0.75, alpha: 1)),
        ("White",   NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)),
        ("Maroon",  NSColor(srgbRed: 0.50, green: 0.00, blue: 0.00, alpha: 1)),
        ("Red",     NSColor(srgbRed: 1.00, green: 0.00, blue: 0.00, alpha: 1)),
        ("Fuchsia", NSColor(srgbRed: 1.00, green: 0.00, blue: 1.00, alpha: 1)),
        ("Yellow",  NSColor(srgbRed: 1.00, green: 1.00, blue: 0.00, alpha: 1)),
        ("Olive",   NSColor(srgbRed: 0.50, green: 0.50, blue: 0.00, alpha: 1)),
        ("Green",   NSColor(srgbRed: 0.00, green: 0.50, blue: 0.00, alpha: 1)),
        ("Teal",    NSColor(srgbRed: 0.00, green: 0.50, blue: 0.50, alpha: 1)),
        ("Lime",    NSColor(srgbRed: 0.00, green: 1.00, blue: 0.00, alpha: 1)),
        ("Purple",  NSColor(srgbRed: 0.50, green: 0.00, blue: 0.50, alpha: 1)),
        ("Navy",    NSColor(srgbRed: 0.00, green: 0.00, blue: 0.50, alpha: 1)),
        ("Blue",    NSColor(srgbRed: 0.00, green: 0.00, blue: 1.00, alpha: 1)),
        ("Aqua",    NSColor(srgbRed: 0.00, green: 1.00, blue: 1.00, alpha: 1)),
    ]

    static func namedColor(at index: Int, fallback: NSColor = .white) -> NSColor {
        guard index >= 0 && index < namedColors.count else { return fallback }
        return namedColors[index].color
    }

    /// Builds a small rounded color square for use as `NSMenuItem.image`.
    static func swatchImage(for color: NSColor, size: CGFloat = 14) -> NSImage {
        let s = NSSize(width: size, height: size)
        let img = NSImage(size: s)
        img.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: s), xRadius: 2, yRadius: 2).fill()
        NSColor.black.withAlphaComponent(0.35).setStroke()
        let border = NSBezierPath(roundedRect: NSRect(origin: .zero, size: s).insetBy(dx: 0.5, dy: 0.5),
                                  xRadius: 2, yRadius: 2)
        border.lineWidth = 0.5
        border.stroke()
        img.unlockFocus()
        return img
    }

    private let label = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true

        let fontSize = CGFloat(UserDefaults.standard.double(forKey: Defaults.subtitleFontSize))
        let fontIndex = UserDefaults.standard.integer(forKey: Defaults.subtitleFont)
        let fontNames = ["", "HelveticaNeue", "Arial", "SFProText-Regular", "PingFangSC-Regular"]
        if fontIndex > 0 && fontIndex < fontNames.count,
           let font = NSFont(name: fontNames[fontIndex], size: fontSize > 0 ? fontSize : 24) {
            label.font = font
        } else {
            label.font = .systemFont(ofSize: fontSize > 0 ? fontSize : 24, weight: .medium)
        }

        let colorIndex = UserDefaults.standard.integer(forKey: Defaults.subtitleColor)
        label.textColor = SubtitleOverlayView.namedColor(at: colorIndex)
        label.alignment = .center
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.maximumNumberOfLines = 3

        label.wantsLayer = true
        label.layer?.shadowColor = NSColor.black.cgColor
        label.layer?.shadowOffset = CGSize(width: 0, height: -1)
        label.layer?.shadowRadius = 3
        label.layer?.shadowOpacity = 0.8

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Observe subtitle preference changes for live updates
        for key in observedKeys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: .new, context: nil)
        }
    }

    private let observedKeys = [
        Defaults.subtitleFont,
        Defaults.subtitleFontSize,
        Defaults.subtitleColor,
        Defaults.subtitleOutlineThickness,
        Defaults.subtitleBackgroundColor,
        Defaults.subtitleBackgroundOpacity,
    ]

    deinit {
        for key in observedKeys {
            UserDefaults.standard.removeObserver(self, forKeyPath: key)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        refreshAppearance()
    }

    func refreshAppearance() {
        let fontSize = CGFloat(UserDefaults.standard.double(forKey: Defaults.subtitleFontSize))
        let fontIndex = UserDefaults.standard.integer(forKey: Defaults.subtitleFont)
        let fontNames = ["", "HelveticaNeue", "Arial", "SFProText-Regular", "PingFangSC-Regular"]
        if fontIndex > 0 && fontIndex < fontNames.count,
           let font = NSFont(name: fontNames[fontIndex], size: fontSize > 0 ? fontSize : 24) {
            label.font = font
        } else {
            label.font = .systemFont(ofSize: fontSize > 0 ? fontSize : 24, weight: .medium)
        }

        let colorIndex = UserDefaults.standard.integer(forKey: Defaults.subtitleColor)
        label.textColor = SubtitleOverlayView.namedColor(at: colorIndex)
    }

    func setText(_ text: String?) {
        guard let text = text, !text.isEmpty else {
            label.stringValue = ""
            isHidden = true
            return
        }
        label.attributedStringValue = applyStyling(to: NSAttributedString(string: text))
        isHidden = false
    }

    func setAttributedText(_ text: NSAttributedString?) {
        guard let text = text, text.length > 0 else {
            label.stringValue = ""
            isHidden = true
            return
        }
        // Re-apply outline/background on top of the parser's font/color attributes
        label.attributedStringValue = applyStyling(to: text)
        isHidden = false
    }

    /// Adds outline-stroke, paragraph alignment, and background-color attributes
    /// to whatever attributed string the parser produced. Negative strokeWidth
    /// makes NSAttributedString fill AND stroke (positive would draw outline only).
    private func applyStyling(to base: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: base)
        let range = NSRange(location: 0, length: result.length)

        let thickness = UserDefaults.standard.integer(forKey: Defaults.subtitleOutlineThickness)
        if thickness > 0 {
            // -value = stroke + fill (outline visible around the filled text)
            result.addAttribute(.strokeWidth, value: -Double(thickness), range: range)
            result.addAttribute(.strokeColor, value: NSColor.black, range: range)
        }

        let bgOpacity = UserDefaults.standard.double(forKey: Defaults.subtitleBackgroundOpacity)
        if bgOpacity > 0 {
            let bgIdx = UserDefaults.standard.integer(forKey: Defaults.subtitleBackgroundColor)
            let bgBase = SubtitleOverlayView.namedColor(at: bgIdx, fallback: .black)
            result.addAttribute(.backgroundColor,
                                value: bgBase.withAlphaComponent(CGFloat(bgOpacity)),
                                range: range)
        }

        // Preserve centering even when parser supplied its own paragraph style
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        result.addAttribute(.paragraphStyle, value: style, range: range)

        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        // Transparent background
    }
}
