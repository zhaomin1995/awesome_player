import Cocoa

class WelcomeView: NSView {
    private let iconView = NSView()
    private let playSymbol = NSImageView()

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

        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(white: 0.15, alpha: 1).cgColor,
            NSColor(white: 0.08, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(gradient)

        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 28
        iconView.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        iconView.layer?.shadowColor = NSColor.black.cgColor
        iconView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        iconView.layer?.shadowRadius = 20
        iconView.layer?.shadowOpacity = 0.5
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .medium)
        let image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")?.withSymbolConfiguration(config)
        playSymbol.image = image
        playSymbol.contentTintColor = NSColor(calibratedRed: 0.55, green: 0.65, blue: 0.95, alpha: 1)
        playSymbol.translatesAutoresizingMaskIntoConstraints = false
        iconView.addSubview(playSymbol)

        let hintLabel = NSTextField(labelWithString: "Drop a video file here or press ⌘O to open")
        hintLabel.font = .systemFont(ofSize: 12, weight: .regular)
        hintLabel.textColor = NSColor(white: 0.45, alpha: 1)
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            iconView.widthAnchor.constraint(equalToConstant: 120),
            iconView.heightAnchor.constraint(equalToConstant: 120),

            playSymbol.centerXAnchor.constraint(equalTo: iconView.centerXAnchor, constant: 4),
            playSymbol.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 24),
        ])
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.first?.frame = bounds
    }
}
