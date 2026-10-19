import XCTest
import AppKit
@testable import MIDIClockController

final class TempoHoldTests: XCTestCase {
    func testShortPressDoesNotRepeatDuringGracePeriod() {
        var ramp = TempoRamp(start: 10)
        XCTAssertEqual(ramp.advance(at: 10.1), 0)
        XCTAssertEqual(ramp.advance(at: 10.39), 0)
        XCTAssertGreaterThan(ramp.advance(at: 10.5), 0)
    }

    func testLaterEqualLengthIntervalsMoveFurther() {
        var ramp = TempoRamp(start: 0)
        var seconds = [Double](repeating: 0, count: 5)
        for tick in 1...50 {
            seconds[(tick - 1) / 10] += ramp.advance(at: Double(tick) / 10)
        }
        for index in 1..<seconds.count {
            XCTAssertGreaterThan(seconds[index], seconds[index - 1])
        }
    }

    func testDelayedUIHasNoCatchUpBurstAndNewHoldResets() {
        var ramp = TempoRamp(start: 0)
        _ = ramp.advance(at: 1)
        XCTAssertLessThanOrEqual(ramp.advance(at: 100), 6)
        XCTAssertEqual(ramp.advance(at: 100), 0)
        var fresh = TempoRamp(start: 100)
        XCTAssertEqual(fresh.advance(at: 100.2), 0)
        XCTAssertLessThanOrEqual(fresh.advance(at: 100.5), 0.3)
    }

    func testRepeaterStopsWithoutTrailingChanges() {
        let hold = TempoHold()
        var total = 0.0
        hold.start(direction: -1, allowed: { true }, action: { total += $0 })
        XCTAssertEqual(total, -0.1, accuracy: 0.00001)
        hold.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.55))
        XCTAssertEqual(total, -0.1, accuracy: 0.00001)
        XCTAssertFalse(hold.isRunning)
        hold.start(direction: 1, allowed: { false }, action: { total += $0 })
        XCTAssertEqual(total, -0.1, accuracy: 0.00001)
        XCTAssertFalse(hold.isRunning)
    }
    func testNewDirectionStartsWithFineStepAndDeactivationCancels() {
        let hold = TempoHold()
        var steps: [Double] = []
        hold.start(direction: 1, allowed: { true }, action: { steps.append($0) })
        hold.start(direction: -1, allowed: { true }, action: { steps.append($0) })
        XCTAssertEqual(steps, [0.1, -0.1])
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        XCTAssertFalse(hold.isRunning)
        RunLoop.main.run(until: Date().addingTimeInterval(0.55))
        XCTAssertEqual(steps, [0.1, -0.1])
    }

}
