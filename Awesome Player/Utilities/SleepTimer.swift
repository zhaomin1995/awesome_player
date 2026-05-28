import Foundation

/// Schedules a future "pause playback" action. Two modes:
///
/// - `.duration(minutes)` — pauses after N wall-clock minutes from `arm()`. A
///   `Timer` runs on the main run loop; `cancel()` invalidates it.
/// - `.endOfFile` — armed flag flipped on; `PlayerViewController` checks it in
///   the engine `didFinishPlaying` callbacks and pauses + clears.
///
/// Singleton because there's only ever one active timer per app session, and
/// the Playback menu delegate needs to read its state for the checkmark.
final class SleepTimer {
    static let shared = SleepTimer()

    enum Mode: Equatable {
        case off
        case duration(minutes: Int)
        case endOfFile
    }

    private(set) var mode: Mode = .off
    /// Wall-clock fire time for `.duration(_)` mode — used by the menu to show
    /// the remaining countdown. `nil` for `.off` and `.endOfFile`.
    private(set) var fireDate: Date?

    private var timer: Timer?
    var onFire: (() -> Void)?

    private init() {}

    func arm(_ mode: Mode) {
        cancel()
        self.mode = mode
        switch mode {
        case .off:
            return
        case .duration(let minutes):
            let interval = TimeInterval(minutes * 60)
            fireDate = Date().addingTimeInterval(interval)
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.fire()
            }
        case .endOfFile:
            fireDate = nil
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        fireDate = nil
        mode = .off
    }

    /// Called by the duration timer OR by PlayerViewController when end-of-file
    /// fires while in `.endOfFile` mode. Clears state and notifies the handler.
    func fire() {
        timer?.invalidate()
        timer = nil
        fireDate = nil
        mode = .off
        onFire?()
    }

    /// Remaining seconds for `.duration` mode, rounded down. Returns 0 for
    /// `.off`/`.endOfFile`. The menu uses this to render "Sleep in 12:34".
    var remainingSeconds: Int {
        guard let fire = fireDate else { return 0 }
        return max(0, Int(fire.timeIntervalSinceNow))
    }
}
