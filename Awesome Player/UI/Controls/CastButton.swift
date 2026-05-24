import Cocoa
import AVKit

class CastButton: NSView {
    private var routePickerView: AVRoutePickerView?
    private let fallbackButton = NSButton()
    private var isAirPlayAvailable = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.setRoutePickerButtonColor(.white, for: .normal)
        picker.setRoutePickerButtonColor(.systemBlue, for: .active)
        addSubview(picker)
        routePickerView = picker

        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: topAnchor),
            picker.bottomAnchor.constraint(equalTo: bottomAnchor),
            picker.leadingAnchor.constraint(equalTo: leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: trailingAnchor),
            picker.widthAnchor.constraint(equalToConstant: 28),
            picker.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    func showPicker() {
        // Programmatically trigger the AVRoutePickerView's internal button
        for subview in routePickerView?.subviews ?? [] {
            if let button = subview as? NSButton {
                button.performClick(nil)
                return
            }
        }
    }

    func setPlayer(_ player: AVPlayer?) {
        routePickerView?.player = player
    }

    func setEnabled(_ enabled: Bool) {
        isAirPlayAvailable = enabled
        routePickerView?.alphaValue = enabled ? 1.0 : 0.4
        routePickerView?.isHidden = false

        if !enabled {
            toolTip = "AirPlay unavailable for this codec"
        } else {
            toolTip = "AirPlay / Cast"
        }
    }
}
