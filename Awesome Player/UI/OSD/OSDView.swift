import Cocoa

class OSDView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let effectView = NSVisualEffectView()
    private var hideTimer: Timer?

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
        alphaValue = 0

        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(label)

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            label.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
        ])
    }

    func show(message: String, duration: TimeInterval = 1.5) {
        label.stringValue = message

        hideTimer?.invalidate()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1.0
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.animator().alphaValue = 0.0
            }
        }
    }
}
