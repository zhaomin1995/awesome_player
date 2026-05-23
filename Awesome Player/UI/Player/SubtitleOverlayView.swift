import Cocoa

class SubtitleOverlayView: NSView {
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

        label.font = .systemFont(ofSize: 24, weight: .medium)
        label.textColor = .white
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
    }

    func setText(_ text: String?) {
        if let text = text, !text.isEmpty {
            label.stringValue = text
            isHidden = false
        } else {
            label.stringValue = ""
            isHidden = true
        }
    }

    func setAttributedText(_ text: NSAttributedString?) {
        if let text = text, text.length > 0 {
            label.attributedStringValue = text
            isHidden = false
        } else {
            label.stringValue = ""
            isHidden = true
        }
    }

    func setBitmapImage(_ image: NSImage?) {
        // Bitmap subtitle support — will use NSImageView in Phase 10
    }

    override func draw(_ dirtyRect: NSRect) {
        // Transparent background
    }
}
