import XCTest
@testable import Awesome_Player

/// Tests for SleepTimer state transitions and remaining-seconds reporting.
/// Doesn't wait for real timer fires — that would slow the test suite by N
/// seconds per duration assertion. Instead exercises the state machine and
/// arithmetic, and explicitly drives `fire()` to simulate the timer firing
/// (which is what the live timer callback does internally too).
final class SleepTimerTests: XCTestCase {

    func testInitialStateIsOff() {
        let t = SleepTimer()
        XCTAssertEqual(t.mode, .off)
        XCTAssertNil(t.fireDate)
        XCTAssertEqual(t.remainingSeconds, 0)
    }

    func testArmDurationSetsModeAndFireDate() {
        let t = SleepTimer()
        let beforeArm = Date()
        t.arm(.duration(minutes: 30))

        if case .duration(let m) = t.mode {
            XCTAssertEqual(m, 30)
        } else {
            XCTFail("expected .duration mode, got \(t.mode)")
        }
        XCTAssertNotNil(t.fireDate)
        // fireDate should be ~30 minutes (1800s) from arm-time. Allow some
        // slack for test-runner scheduling jitter.
        let expectedFire = beforeArm.addingTimeInterval(1800)
        XCTAssertEqual(t.fireDate!.timeIntervalSince(expectedFire), 0, accuracy: 2.0)
        // Remaining seconds: same arithmetic, should be near 1800.
        XCTAssertGreaterThan(t.remainingSeconds, 1795)
        XCTAssertLessThanOrEqual(t.remainingSeconds, 1800)
    }

    func testArmEndOfFileLeavesFireDateNil() {
        let t = SleepTimer()
        t.arm(.endOfFile)
        XCTAssertEqual(t.mode, .endOfFile)
        // EOF mode is event-driven, not time-driven — fireDate is meaningless.
        XCTAssertNil(t.fireDate)
        XCTAssertEqual(t.remainingSeconds, 0)
    }

    func testCancelResetsState() {
        let t = SleepTimer()
        t.arm(.duration(minutes: 15))
        XCTAssertNotNil(t.fireDate)
        t.cancel()
        XCTAssertEqual(t.mode, .off)
        XCTAssertNil(t.fireDate)
        XCTAssertEqual(t.remainingSeconds, 0)
    }

    func testReArmReplacesPriorMode() {
        let t = SleepTimer()
        t.arm(.duration(minutes: 15))
        let firstFireDate = t.fireDate
        t.arm(.duration(minutes: 60))
        // Mode now reflects the second arm, and fireDate moved further out.
        if case .duration(let m) = t.mode {
            XCTAssertEqual(m, 60)
        } else {
            XCTFail("expected .duration(60), got \(t.mode)")
        }
        XCTAssertNotNil(firstFireDate)
        XCTAssertGreaterThan(t.fireDate!, firstFireDate!)
    }

    func testReArmFromDurationToEndOfFileClearsFireDate() {
        let t = SleepTimer()
        t.arm(.duration(minutes: 15))
        XCTAssertNotNil(t.fireDate)
        t.arm(.endOfFile)
        XCTAssertEqual(t.mode, .endOfFile)
        XCTAssertNil(t.fireDate)
    }

    func testFireResetsStateAndCallsHandler() {
        let t = SleepTimer()
        var fired = false
        t.onFire = { fired = true }
        t.arm(.duration(minutes: 30))
        XCTAssertNotNil(t.fireDate)
        t.fire()
        XCTAssertTrue(fired)
        XCTAssertEqual(t.mode, .off)
        XCTAssertNil(t.fireDate)
    }

    func testFireWhenOffStillCallsHandler() {
        // Edge case: PlayerViewController calls fire() at EOF only when
        // mode == .endOfFile, but the handler should be robust to a stray
        // call after cancel/never-armed (no crash, no state damage).
        let t = SleepTimer()
        var fired = false
        t.onFire = { fired = true }
        t.fire()
        XCTAssertTrue(fired)
        XCTAssertEqual(t.mode, .off)
    }

    func testArmOffIsNoOp() {
        let t = SleepTimer()
        t.arm(.off)
        XCTAssertEqual(t.mode, .off)
        XCTAssertNil(t.fireDate)
    }
}
