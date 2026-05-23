import Cocoa

class ABLoopButton: NSView {
    var onToggle: (() -> Void)?

    private let button = NSButton()
    private var state: ABLoopDisplayState = .inactive

    enum ABLoopDisplayState {
        case inactive
        case settingA
        case active
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        button.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: "A-B Loop")
        button.isBordered = false
        button.contentTintColor = .white
        button.target = self
        button.action = #selector(buttonClicked)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])

        updateAppearance()
    }

    @objc private func buttonClicked() {
        onToggle?()
    }

    func setState(_ newState: ABLoopDisplayState) {
        state = newState
        updateAppearance()
    }

    private func updateAppearance() {
        switch state {
        case .inactive:
            button.contentTintColor = .white
            button.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: "A-B Loop")
            toolTip = "Set A point (R)"
        case .settingA:
            button.contentTintColor = .systemGreen
            button.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: "A point set")
            toolTip = "A set — click to set B point"
        case .active:
            button.contentTintColor = .systemOrange
            button.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: "Looping")
            toolTip = "Looping A-B — click to clear"
        }
    }
}
