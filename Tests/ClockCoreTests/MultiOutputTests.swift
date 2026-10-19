import XCTest
import CoreMIDI
@testable import ClockCore

final class MultiOutputTests: XCTestCase {
    struct Event: Equatable { let endpoint: UInt32; let status: UInt8; let time: Double }
    let a = MIDIOutput(id: 1, endpoint: 1, name: "A")
    let b = MIDIOutput(id: 2, endpoint: 2, name: "B")

    func testSharedTimestampsDuringTempoChangesAndRestart() throws {
        var time = 0.0
        var events: [Event] = []
        let engine = MIDIClockEngine(clock: { time }, wait: { time += $0 }, sender: {
            events.append(Event(endpoint: $0, status: $1, time: $2))
        })
        for _ in 0..<20 {
            try engine.start(outputs: [a, b, a], bpm: 120)
            for step in 0..<50 {
                time += 0.002
                engine.setBPM(step < 25 ? 60 : 300)
                engine.pumpForTesting()
            }
            try engine.stop()
        }
        let first = events.filter { $0.endpoint == 1 }
        let second = events.filter { $0.endpoint == 2 }
        XCTAssertEqual(first.count, second.count)
        XCTAssertEqual(first.filter { $0.status == 0xFA }.count, 20)
        XCTAssertGreaterThan(first.filter { $0.status == 0xF8 }.count, 0)
        for (x, y) in zip(first, second) {
            XCTAssertEqual(x.status, y.status)
            XCTAssertEqual(x.time, y.time)
        }
        XCTAssertThrowsError(try engine.start(outputs: [], bpm: 120))
    }

    func testIndependentEnginesShareStartTempoChangeAndStopDeadlines() throws {
        var time = 0.0
        var first: [Double] = []
        var second: [Double] = []
        let one = MIDIClockEngine(clock: { time }, wait: { time += $0 }, sender: { _, status, stamp in
            if status == 0xF8 { first.append(stamp) }
        })
        let two = MIDIClockEngine(clock: { time }, wait: { time += $0 }, sender: { _, status, stamp in
            if status == 0xF8 { second.append(stamp) }
        })
        try one.start(outputs: [a], bpm: 120, scheduledAt: 0.05)
        try two.start(outputs: [b], bpm: 120, scheduledAt: 0.05)
        for index in 1...500 {
            time = Double(index) * 0.002
            if index == 70 {
                one.scheduleBPM(240, at: 0.20)
                two.scheduleBPM(240, at: 0.20)
            }
            one.pumpForTesting()
            time += 0.0005
            two.pumpForTesting()
        }
        try one.scheduleStop(at: 1.05)
        try two.scheduleStop(at: 1.05)
        one.shutdown(); two.shutdown()
        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(first.count, 60)
        let gaps = zip(first, first.dropFirst()).map { $1 - $0 }
        XCTAssertTrue(gaps.contains { abs($0 - 60 / (120 * 24)) < 1e-9 })
        XCTAssertTrue(gaps.contains { abs($0 - 60 / (240 * 24)) < 1e-9 })
    }

    func testPartialStartFailureStopsEveryOutput() {
        var time = 0.0
        var events: [Event] = []
        let engine = MIDIClockEngine(clock: { time }, wait: { time += $0 }, sender: { endpoint, status, deadline in
            if endpoint == 2 && status == 0xFA { throw MIDIError(operation: "injected", status: -1) }
            events.append(Event(endpoint: endpoint, status: status, time: deadline))
        })
        XCTAssertThrowsError(try engine.start(outputs: [a, b], bpm: 120))
        XCTAssertEqual(events.filter { $0.endpoint == 1 }.map(\.status), [0xFA, 0xFC])
        XCTAssertEqual(events.filter { $0.endpoint == 2 }.map(\.status), [0xFC])
        XCTAssertGreaterThan(events.last!.time, events.first!.time)
        let count = events.count
        engine.pumpForTesting()
        XCTAssertEqual(events.count, count)
    }

    func testDisconnectedFirstOutputDoesNotPreventStoppingOtherOutputs() throws {
        var time = 0.0
        var disconnected = false
        var events: [Event] = []
        let engine = MIDIClockEngine(clock: { time }, wait: { time += $0 }, sender: { endpoint, status, deadline in
            if disconnected && endpoint == 1 { throw MIDIError(operation: "disconnected", status: -1) }
            events.append(Event(endpoint: endpoint, status: status, time: deadline))
        })
        try engine.start(outputs: [a, b], bpm: 120)
        disconnected = true
        time = 0.002
        engine.pumpForTesting()
        let second = events.filter { $0.endpoint == 2 }
        XCTAssertEqual(second.map(\.status), [0xFA, 0xF8, 0xFC])
        XCTAssertGreaterThan(second[2].time, second[1].time)
        let count = events.count
        time += 1
        engine.pumpForTesting()
        XCTAssertEqual(events.count, count)
    }
}
