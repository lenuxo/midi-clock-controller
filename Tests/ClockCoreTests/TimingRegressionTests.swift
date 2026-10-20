import XCTest
@testable import ClockCore

final class TimingRegressionTests: XCTestCase {
    private let output = MIDIOutput(id: 1, endpoint: 1, name: "Test only")

    func testContinueDrainsStopAndResetsTempoWithoutOldClocks() throws {
        let host = Host()
        let engine = host.engine()
        try engine.start(output: output, bpm: 120)
        host.time = 0.002
        engine.pumpForTesting()
        engine.scheduleBPM(20, at: 0.2)
        try engine.scheduleStop(at: 0.05)
        let oldStop = try XCTUnwrap(host.events.last)
        try engine.resume(outputs: [output], bpm: 300)
        let resume = try XCTUnwrap(host.events.last)
        XCTAssertEqual(resume.status, 0xFB)
        XCTAssertGreaterThan(resume.time, oldStop.time)
        let offset = host.events.count
        for _ in 0..<150 {
            host.time += 0.002
            engine.pumpForTesting()
        }
        let ticks = Array(host.events.dropFirst(offset)).filter { $0.status == 0xF8 }
        XCTAssertGreaterThan(ticks.count, 30)
        XCTAssertEqual(try XCTUnwrap(ticks.first).time - resume.time, 0.001, accuracy: 1e-12)
        for (a, b) in zip(ticks, ticks.dropFirst()) {
            XCTAssertEqual(b.time - a.time, 60 / (300 * 24), accuracy: 1e-12)
        }
        try engine.stop()
        for (a, b) in zip(host.events, host.events.dropFirst()) { XCTAssertLessThan(a.time, b.time) }
    }

    func testRapidMixedStartContinueStopHasNoBacklogOrDuplicateTransport() throws {
        let host = Host()
        let engine = host.engine()
        for index in 0..<100 {
            let before = host.time
            if index.isMultiple(of: 2) { try engine.start(output: output, bpm: 120) }
            else { try engine.resume(outputs: [output], bpm: 300) }
            // Repeated play commands while running must not reset the receiver.
            try engine.resume(outputs: [output], bpm: 20)
            try engine.start(output: output, bpm: 20)
            try engine.scheduleStop(at: host.time + 0.05)
            engine.drainPendingStop()
            XCTAssertLessThan(host.time - before, 0.051)
            engine.pumpForTesting()
        }
        XCTAssertEqual(host.events.count, 200)
        for index in 0..<100 {
            XCTAssertEqual(host.events[index * 2].status, index.isMultiple(of: 2) ? 0xFA : 0xFB)
            XCTAssertEqual(host.events[index * 2 + 1].status, 0xFC)
        }
        for (a, b) in zip(host.events, host.events.dropFirst()) { XCTAssertLessThan(a.time, b.time) }
    }

    func testOldFailureCannotInvalidateContinueRun() throws {
        let host = Host()
        let engine = host.engine()
        var failures = 0
        engine.onFailure = { _ in failures += 1 }
        try engine.start(output: output, bpm: 300)
        host.time = 0.1
        engine.pumpForTesting()
        try engine.resume(outputs: [output], bpm: 120)
        let flushed = expectation(description: "old failure delivered")
        DispatchQueue.main.async { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
        XCTAssertEqual(failures, 0)
        engine.shutdown()
        XCTAssertEqual(host.events.map(\.status), [0xFA, 0xFC, 0xFB, 0xFC])
    }

    func testLateWakeDoesNotCompressNextInterval() throws {
        let host = Host()
        let engine = host.engine()
        try engine.start(output: output, bpm: 300)
        host.time = 0.010 // first tick was due at .009
        engine.pumpForTesting()
        host.time = 0.013
        engine.pumpForTesting()
        let ticks = host.events.filter { $0.status == 0xF8 }
        XCTAssertEqual(ticks.count, 2)
        XCTAssertEqual(ticks[1].time - ticks[0].time, 60 / (300 * 24), accuracy: 1e-12)
        try engine.stop()
    }

    func testHundredImmediateStartStopCyclesDoNotBuildFutureBacklog() throws {
        let host = Host()
        let engine = host.engine()
        for _ in 0..<100 {
            try engine.start(output: output, bpm: 300)
            let requested = host.time
            try engine.stop()
            XCTAssertLessThanOrEqual(host.time - requested, 0.010)
            XCTAssertLessThanOrEqual(try XCTUnwrap(host.events.last).time, host.time)
        }
        XCTAssertEqual(host.events.count, 200)
        for (index, event) in host.events.enumerated() {
            XCTAssertEqual(event.status, index.isMultiple(of: 2) ? 0xFA : 0xFC)
        }
        for (a, b) in zip(host.events, host.events.dropFirst()) { XCTAssertLessThan(a.time, b.time) }
    }

    func testLateWakeBeyondIntervalStopsWithoutBurst() throws {
        let host = Host()
        let engine = host.engine()
        try engine.start(output: output, bpm: 300)
        host.time = 0.030
        engine.pumpForTesting()
        XCTAssertEqual(host.events.map(\.status), [0xFA, 0xFC])
        host.time += 1
        engine.pumpForTesting()
        XCTAssertEqual(host.events.count, 2)
    }

    func testContinuousTempoEditsPreserveValidPulseSpacing() throws {
        let host = Host()
        let engine = host.engine()
        try engine.start(output: output, bpm: 120)
        let tempos = [20.0, 300, 60, 240, 123.4, 120]
        let allowedGaps = tempos.map { 60 / ($0 * 24) }
        for step in 1...5000 {
            host.time = Double(step) * 0.002
            engine.setBPM(tempos[(step / 17) % tempos.count])
            engine.pumpForTesting()
        }
        try engine.stop()
        let ticks = host.events.filter { $0.status == 0xF8 }
        XCTAssertGreaterThan(ticks.count, 150)
        for (a, b) in zip(ticks, ticks.dropFirst()) {
            let gap = b.time - a.time
            XCTAssertTrue(allowedGaps.contains { abs($0 - gap) < 1e-9 }, "Unexpected pulse gap: \(gap)")
        }
        XCTAssertEqual(host.events.first?.status, 0xFA)
        XCTAssertEqual(host.events.last?.status, 0xFC)
        XCTAssertEqual(host.events.filter { $0.status == 0xFA }.count, 1)
        XCTAssertEqual(host.events.filter { $0.status == 0xFC }.count, 1)
    }

    func testShutdownDrainsFinalStopAndDuplicateCallsAreIdempotent() throws {
        let host = Host()
        let engine = host.engine()
        try engine.start(output: output, bpm: 120)
        try engine.start(output: output, bpm: 240)
        host.time = 0.002
        engine.pumpForTesting()
        engine.shutdown()
        let count = host.events.count
        engine.shutdown()
        try engine.stop()
        engine.pumpForTesting()
        XCTAssertEqual(host.events.count, count)
        XCTAssertEqual(host.events.last?.status, 0xFC)
        XCTAssertLessThanOrEqual(try XCTUnwrap(host.events.last).time, host.time)
    }

    func testOldFailureNotificationCannotStopNewRun() throws {
        let host = Host()
        let engine = host.engine()
        let flushed = expectation(description: "main queue drained")
        var failures = 0
        engine.onFailure = { _ in failures += 1 }
        try engine.start(output: output, bpm: 300)
        host.time = 0.1
        engine.pumpForTesting() // queues failure on main queue
        try engine.start(output: output, bpm: 120)
        DispatchQueue.main.async { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
        XCTAssertEqual(failures, 0)
        try engine.stop()
    }
}

private final class Host {
    struct Event { let status: UInt8; let time: Double }
    var time = 0.0
    var events: [Event] = []
    func engine() -> MIDIClockEngine {
        MIDIClockEngine(clock: { self.time }, wait: { self.time += $0 }, sender: {
            self.events.append(Event(status: $0, time: $1))
        })
    }
}
