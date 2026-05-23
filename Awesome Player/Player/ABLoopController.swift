import AVFoundation
import CoreMedia

enum ABLoopState {
    case inactive
    case settingA(CMTime)
    case active(a: CMTime, b: CMTime)
}

protocol ABLoopDelegate: AnyObject {
    func abLoopStateChanged(_ state: ABLoopState)
    func abLoopShouldSeek(to time: CMTime)
}

class ABLoopController {
    weak var delegate: ABLoopDelegate?

    private(set) var state: ABLoopState = .inactive
    var gap: TimeInterval = 0

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    var pointA: CMTime? {
        switch state {
        case .settingA(let a): return a
        case .active(let a, _): return a
        default: return nil
        }
    }

    var pointB: CMTime? {
        if case .active(_, let b) = state { return b }
        return nil
    }

    func toggle(currentTime: CMTime) {
        switch state {
        case .inactive:
            state = .settingA(currentTime)
            delegate?.abLoopStateChanged(state)

        case .settingA(let a):
            if currentTime > a {
                state = .active(a: a, b: currentTime)
            } else {
                state = .active(a: currentTime, b: a)
            }
            delegate?.abLoopStateChanged(state)

        case .active:
            state = .inactive
            delegate?.abLoopStateChanged(state)
        }
    }

    func checkLoop(currentTime: CMTime) {
        guard case .active(let a, let b) = state else { return }
        if CMTimeCompare(currentTime, b) >= 0 {
            if gap > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + gap) { [weak self] in
                    self?.delegate?.abLoopShouldSeek(to: a)
                }
            } else {
                delegate?.abLoopShouldSeek(to: a)
            }
        }
    }

    func setPointA(_ time: CMTime) {
        switch state {
        case .active(_, let b):
            state = .active(a: time, b: b)
        default:
            state = .settingA(time)
        }
        delegate?.abLoopStateChanged(state)
    }

    func setPointB(_ time: CMTime) {
        guard case .settingA(let a) = state else { return }
        state = .active(a: a, b: time)
        delegate?.abLoopStateChanged(state)
    }

    func clear() {
        state = .inactive
        delegate?.abLoopStateChanged(state)
    }
}
