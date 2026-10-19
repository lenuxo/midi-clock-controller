import XCTest
@testable import ClockCore

final class ClockScheduleTests: XCTestCase {
    func testTwentyFourPulsesPerQuarterNote() {
        var clock = ClockSchedule(bpm: 120, start: 100)
        let pulses = (0..<24).compactMap { _ in clock.pop(through: 100.499999) }
        XCTAssertEqual(pulses.count, 24)
        XCTAssertEqual(clock.next, 100.5, accuracy: 1e-10)
        XCTAssertNil(clock.pop(through: 100.499999))
    }

    func testLongRunDoesNotAccumulateRoundingDrift() {
        var clock = ClockSchedule(bpm: 123.4, start: 1000)
        for _ in 0..<1_000_000 { _ = clock.pop(through: .greatestFiniteMagnitude) }
        XCTAssertEqual(clock.next, 1000 + 1_000_000 * 60 / (123.4 * 24), accuracy: 1e-9)
    }

    func testTempoChangeKeepsNextDeadlineThenUsesNewSpacing() {
        var clock = ClockSchedule(bpm: 120, start: 1)
        _ = clock.pop(through: 1)
        let deadline = clock.next
        clock.setBPM(60)
        XCTAssertEqual(clock.next, deadline)
        XCTAssertEqual(clock.pop(through: deadline), deadline)
        XCTAssertEqual(clock.next - deadline, 1 / 24, accuracy: 1e-10)
    }

    func testInvalidTempoIsSafe() {
        XCTAssertEqual(ClockSchedule.clamp(.nan), 120)
        XCTAssertEqual(ClockSchedule.clamp(.infinity), 120)
        XCTAssertEqual(ClockSchedule.clamp(0), 20)
        XCTAssertEqual(ClockSchedule.clamp(500), 300)
    }
}
