import XCTest
@testable import ClockCore

final class BeatClockTests: XCTestCase {
    private let output = MIDIOutput(id: 1, endpoint: 1, name: "Private test")

    func testTwoEnginesUseSameBeatGridAcrossRepeatedTempoChanges() throws {
        let clock = TestBeatClock()
        var now = 0.0
        var a: [Double] = [], b: [Double] = []
        let one = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { status, at in if status == 0xF8 { a.append(at) } })
        let two = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { status, at in if status == 0xF8 { b.append(at) } })
        for engine in [one, two] {
            engine.setBeatClock(clock)
            try engine.start(outputs: [output], bpm: 120, scheduledAt: 0.05)
        }
        for step in 1...4000 {
            now = Double(step) * 0.002
            if step.isMultiple(of: 500) { clock.setTempo(step.isMultiple(of: 1000) ? 90 : 240, at: now + 0.01) }
            one.pumpForTesting(); two.pumpForTesting()
        }
        XCTAssertEqual(a, b)
        XCTAssertGreaterThan(a.count, 200)
        XCTAssertEqual(a.first!, 0.5, accuracy: 1e-9)
        XCTAssertTrue(zip(a, a.dropFirst()).allSatisfy { $1 > $0 })
        one.shutdown(); two.shutdown()
    }

    func testArmedCancellationNeverSendsOrWaitsForOldTransport() throws {
        let clock = TestBeatClock()
        var now = 0.0
        var events: [UInt8] = []
        let engine = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { status, _ in events.append(status) })
        engine.setBeatClock(clock, quantum: 4)
        for _ in 0..<100 {
            try engine.start(outputs: [output], bpm: 120)
            XCTAssertTrue(engine.waitingForBeat)
            engine.pumpForTesting()
            try engine.stop()
            XCTAssertFalse(engine.waitingForBeat)
        }
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(now, 0)
        now = 3
        engine.pumpForTesting()
        XCTAssertTrue(events.isEmpty)
    }

    func testFirstClockOnBoundaryAndContinueAfterStopHasNoOldPulses() throws {
        let clock = TestBeatClock()
        var now = 0.0
        var events: [(UInt8, Double)] = []
        let engine = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { events.append(($0, $1)) })
        engine.setBeatClock(clock)
        try engine.start(outputs: [output], bpm: 120)
        for i in 1...350 { now = Double(i) * 0.002; engine.pumpForTesting() }
        XCTAssertEqual(events.first!.0, 0xFA)
        XCTAssertEqual(events[0].1, 0.499, accuracy: 1e-9)
        XCTAssertEqual(events[1].1, 0.5, accuracy: 1e-9)
        try engine.stop()
        let stoppedCount = events.count
        now += 1
        engine.pumpForTesting()
        XCTAssertEqual(events.count, stoppedCount)
        try engine.resume(outputs: [output], bpm: 120)
        for _ in 0..<300 { now += 0.002; engine.pumpForTesting() }
        XCTAssertEqual(events[stoppedCount].0, 0xFB)
        XCTAssertTrue(zip(events, events.dropFirst()).allSatisfy { $0.1 < $1.1 })
        engine.shutdown()
    }

    func testPartialQuantizedStartFailureSendsStopToAcceptedDestinations() throws {
        let clock = TestBeatClock()
        var now = 0.0
        var events: [(UInt8, Double)] = []
        let engine = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { endpoint, status, at in
            if endpoint == 2 && status == 0xFA { throw MIDIError(operation: "Injected", status: -1) }
            if endpoint == 1 { events.append((status, at)) }
        })
        engine.setBeatClock(clock)
        try engine.start(outputs: [output, MIDIOutput(id: 2, endpoint: 2, name: "Failure")], bpm: 120)
        now = 0.495
        engine.pumpForTesting()
        XCTAssertEqual(events.map(\.0), [0xFA, 0xFC])
        XCTAssertGreaterThan(events[1].1, events[0].1)
    }

    func testClockDriftUsesBeatMappingInsteadOfDisplayedTempo() throws {
        let clock = TestBeatClock()
        clock.secondsPerBeat = 0.5001 // Same nominal BPM, but actual beat mapping includes drift.
        var now = 0.0
        var ticks: [Double] = []
        let engine = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { status, at in if status == 0xF8 { ticks.append(at) } })
        engine.setBeatClock(clock)
        try engine.start(outputs: [output], bpm: 120)
        for i in 1...1000 { now = Double(i) * 0.002; engine.pumpForTesting() }
        XCTAssertGreaterThan(ticks.count, 24)
        for (a, b) in zip(ticks, ticks.dropFirst()) { XCTAssertEqual(b - a, 0.5001 / 24, accuracy: 1e-9) }
        engine.shutdown()
    }

    func testDetachingKeepsRunningAndUsesLastTempoLocally() throws {
        let clock = TestBeatClock()
        var now = 0.0
        var ticks: [Double] = []
        let engine = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { status, at in if status == 0xF8 { ticks.append(at) } })
        engine.setBeatClock(clock)
        try engine.start(outputs: [output], bpm: 120)
        for i in 1...350 { now = Double(i) * 0.002; engine.pumpForTesting() }
        engine.setBeatClock(nil)
        let offset = ticks.count
        clock.setTempo(240, at: now)
        for _ in 0..<200 { now += 0.002; engine.pumpForTesting() }
        let after = Array(ticks.dropFirst(offset))
        XCTAssertGreaterThan(after.count, 10)
        for (a, b) in zip(after, after.dropFirst()) { XCTAssertEqual(b - a, 0.5 / 24, accuracy: 1e-9) }
        engine.shutdown()
    }
}

private final class TestBeatClock: BeatClock {
    var anchorTime = 0.0, anchorBeat = 0.0, secondsPerBeat = 0.5, bpm = 120.0
    func timeline(at time: Double) -> BeatTimeline {
        BeatTimeline(hostTime: anchorTime, beat: anchorBeat, secondsPerBeat: secondsPerBeat, bpm: bpm)
    }
    func setTempo(_ tempo: Double, at time: Double) {
        anchorBeat = timeline(at: time).beat(at: time)
        anchorTime = time; bpm = tempo; secondsPerBeat = 60 / tempo
    }
}

extension BeatClockTests {
    func testAttachingRunningLocalDeviceDoesNotCompressQueuedInterval() throws {
        let clock = TestBeatClock()
        clock.anchorBeat = 0.37
        var now = 0.0
        var ticks: [Double] = []
        let engine = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { status, at in if status == 0xF8 { ticks.append(at) } })
        try engine.start(outputs: [output], bpm: 120)
        for i in 1...200 { now = Double(i) * 0.002; engine.pumpForTesting() }
        engine.setBeatClock(clock)
        for _ in 0..<500 { now += 0.002; engine.pumpForTesting() }
        XCTAssertGreaterThan(ticks.count, 50)
        for (a, b) in zip(ticks, ticks.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 0.5 / 24 - 1e-9) }
        engine.shutdown()
    }

    func testOneHourRemainsOnBeatGridWithoutAccumulatingPhaseError() throws {
        let clock = TestBeatClock()
        var now = 0.0
        var count = 0
        var largestError = 0.0
        let engine = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { status, at in
            if status == 0xF8 {
                count += 1
                let position = at * 2 * 24
                largestError = max(largestError, abs(position - position.rounded()))
            }
        })
        engine.setBeatClock(clock)
        try engine.start(outputs: [output], bpm: 120)
        for step in 1...1_800_000 { now = Double(step) * 0.002; engine.pumpForTesting() }
        XCTAssertGreaterThan(count, 172_000)
        XCTAssertLessThan(largestError, 0.0001)
        engine.shutdown()
    }
}

extension BeatClockTests {
    func testTempoRatioChangeRebasesWithoutFreezingOrBursting() throws {
        let clock = RatioClock()
        var now = 0.0
        var ticks: [Double] = []
        let engine = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { status, at in if status == 0xF8 { ticks.append(at) } })
        engine.setBeatClock(clock)
        try engine.start(outputs: [output], bpm: 120)
        for i in 1...500 { now = Double(i) * 0.002; engine.pumpForTesting() }
        let count = ticks.count
        clock.scale = 0.25
        for _ in 0..<500 { now += 0.002; engine.pumpForTesting() }
        XCTAssertGreaterThan(ticks.count - count, 8)
        XCTAssertTrue(zip(ticks, ticks.dropFirst()).allSatisfy { $1 > $0 })
        for (a, b) in zip(ticks.dropFirst(count), ticks.dropFirst(count + 1)) {
            XCTAssertEqual(b - a, 2.0 / 24, accuracy: 1e-9)
        }
        engine.shutdown()
    }
}

private final class RatioClock: BeatClock {
    var scale = 1.0
    func timeline(at time: Double) -> BeatTimeline {
        BeatTimeline(hostTime: 0, beat: 0, secondsPerBeat: 0.5 / scale, bpm: 120 * scale, beatScale: scale)
    }
}

extension BeatClockTests {
    func testInvalidAttachedTimelineStopsInsteadOfFreezingOutput() throws {
        let clock = TestBeatClock()
        clock.bpm = .nan
        var now = 0.0
        var events: [UInt8] = []
        let engine = MIDIClockEngine(clock: { now }, wait: { now += $0 }, sender: { status, _ in events.append(status) })
        try engine.start(outputs: [output], bpm: 120)
        engine.setBeatClock(clock)
        engine.pumpForTesting()
        XCTAssertEqual(events, [0xFA, 0xFC])
        engine.shutdown()
    }
}
