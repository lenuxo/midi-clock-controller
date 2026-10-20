import XCTest
import CoreMIDI
import CoreAudio
@testable import ClockCore

/// Uses a private virtual destination; never sends messages to physical hardware.
final class MIDIIntegrationTests: XCTestCase {
    func testTransportTempoChangeAndRestartThroughCoreMIDI() throws {
        let capture = Capture()
        var client: MIDIClientRef = 0
        var endpoint: MIDIEndpointRef = 0
        let clientStatus = MIDIClientCreateWithBlock("Clock test receiver" as CFString, &client, nil)
        guard clientStatus == noErr else {
            if ProcessInfo.processInfo.environment["REQUIRE_MIDI_TESTS"] == "1" {
                XCTFail("CoreMIDI unavailable: \(clientStatus)")
                return
            }
            throw XCTSkip("CoreMIDI service unavailable in this environment: \(clientStatus)")
        }
        defer { MIDIClientDispose(client) }
        XCTAssertEqual(MIDIDestinationCreateWithProtocol(client, "Clock test destination" as CFString,
                                                        ._1_0, &endpoint) { events, _ in
            var packetPointer = UnsafeRawPointer(events)
                .advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
                .assumingMemoryBound(to: MIDIEventPacket.self)
            for _ in 0..<events.pointee.numPackets {
                let packet = packetPointer.pointee
                withUnsafeBytes(of: packet.words) { bytes in
                    let words = bytes.bindMemory(to: UInt32.self)
                    for i in 0..<Int(packet.wordCount) {
                        capture.append(status: UInt8((words[i] >> 16) & 0xFF), time: packet.timeStamp)
                    }
                }
                packetPointer = UnsafePointer(MIDIEventPacketNext(packetPointer))
            }
        }, noErr)
        let capture2 = Capture()
        var endpoint2: MIDIEndpointRef = 0
        XCTAssertEqual(MIDIDestinationCreateWithProtocol(client, "Clock test destination 2" as CFString,
                                                        ._1_0, &endpoint2) { events, _ in
            var packetPointer = UnsafeRawPointer(events)
                .advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
                .assumingMemoryBound(to: MIDIEventPacket.self)
            for _ in 0..<events.pointee.numPackets {
                let packet = packetPointer.pointee
                withUnsafeBytes(of: packet.words) { bytes in
                    let words = bytes.bindMemory(to: UInt32.self)
                    for i in 0..<Int(packet.wordCount) {
                        capture2.append(status: UInt8((words[i] >> 16) & 0xFF), time: packet.timeStamp)
                    }
                }
                packetPointer = UnsafePointer(MIDIEventPacketNext(packetPointer))
            }
        }, noErr)
        defer { MIDIEndpointDispose(endpoint2) }
        defer { MIDIEndpointDispose(endpoint) }
        let engine = try MIDIClockEngine()
        let output = try XCTUnwrap(engine.outputs().first { $0.endpoint == endpoint })
        let output2 = try XCTUnwrap(engine.outputs().first { $0.endpoint == endpoint2 })
        try engine.start(outputs: [output, output2], bpm: 120)
        Thread.sleep(forTimeInterval: 0.27)
        engine.setBPM(240)
        Thread.sleep(forTimeInterval: 0.27)
        try engine.stop()
        Thread.sleep(forTimeInterval: 0.04)
        let first = capture.snapshot()
        XCTAssertEqual(first.first?.status, 0xFA)
        XCTAssertEqual(first.last?.status, 0xFC)
        let clocks = first.filter { $0.status == 0xF8 }
        XCTAssertGreaterThan(clocks.count, 25)
        let frequency = AudioGetHostClockFrequency()
        let gaps = zip(clocks, clocks.dropFirst()).map { (Double($1.time) - Double($0.time)) / frequency }
        XCTAssertTrue(gaps.contains { abs($0 - 60 / (120 * 24)) < 0.00001 })
        XCTAssertTrue(gaps.contains { abs($0 - 60 / (240 * 24)) < 0.00001 })
        for pair in zip(first, first.dropFirst()) { XCTAssertLessThan(pair.0.time, pair.1.time) }
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(capture.snapshot().count, first.count, "Stop must end clock output")
        try engine.start(outputs: [output, output2], bpm: 120)
        try engine.stop()
        try engine.resume(outputs: [output, output2], bpm: 120)
        Thread.sleep(forTimeInterval: 0.08)
        engine.shutdown()
        Thread.sleep(forTimeInterval: 0.04)
        let all = capture.snapshot()
        XCTAssertEqual(all.filter { $0.status == 0xFA }.count, 2)
        XCTAssertEqual(all.filter { $0.status == 0xFB }.count, 1)
        XCTAssertEqual(all.filter { $0.status == 0xFC }.count, 3)
        XCTAssertEqual(all.last?.status, 0xFC)
        for pair in zip(all, all.dropFirst()) { XCTAssertLessThan(pair.0.time, pair.1.time) }

        // Stress the real system transport, not just the deterministic test sink.
        for index in 0..<100 {
            if index.isMultiple(of: 2) { try engine.start(outputs: [output, output2], bpm: 300) }
            else { try engine.resume(outputs: [output, output2], bpm: 300) }
            try engine.stop()
        }
        Thread.sleep(forTimeInterval: 0.04)
        let stress = Array(capture.snapshot().dropFirst(all.count))
        XCTAssertEqual(stress.filter { $0.status == 0xFA }.count, 50)
        XCTAssertEqual(stress.filter { $0.status == 0xFB }.count, 50)
        XCTAssertEqual(stress.filter { $0.status == 0xFC }.count, 100)
        var playing = false
        for event in stress {
            switch event.status {
            case 0xFA, 0xFB: XCTAssertFalse(playing); playing = true
            case 0xFC: XCTAssertTrue(playing); playing = false
            case 0xF8: XCTAssertTrue(playing, "Clock outside Start/Stop")
            default: XCTFail("Unexpected status")
            }
        }
        XCTAssertFalse(playing)
        for pair in zip(stress, stress.dropFirst()) { XCTAssertLessThan(pair.0.time, pair.1.time) }
        XCTAssertLessThanOrEqual(try XCTUnwrap(stress.last).time, AudioGetCurrentHostTime())

        let offset = capture.snapshot().count
        try engine.start(outputs: [output, output2], bpm: 20)
        for bpm in [20.0, 300, 60, 240] {
            engine.setBPM(bpm)
            Thread.sleep(forTimeInterval: 0.35)
        }
        engine.shutdown()
        Thread.sleep(forTimeInterval: 0.04)
        let tempoEvents = Array(capture.snapshot().dropFirst(offset))
        XCTAssertEqual(tempoEvents.first?.status, 0xFA)
        XCTAssertEqual(tempoEvents.last?.status, 0xFC)
        XCTAssertEqual(tempoEvents.filter { $0.status == 0xFA }.count, 1)
        let tempoTicks = tempoEvents.filter { $0.status == 0xF8 }
        XCTAssertGreaterThan(tempoTicks.count, 40)
        let tempoGaps = zip(tempoTicks, tempoTicks.dropFirst()).map { (Double($1.time) - Double($0.time)) / frequency }
        for bpm in [20.0, 300, 60, 240] {
            XCTAssertTrue(tempoGaps.contains { abs($0 - 60 / (bpm * 24)) < 0.00001 })
        }
        XCTAssertTrue(tempoGaps.allSatisfy { $0 >= 60 / (300 * 24) - 0.00001 })
        XCTAssertEqual(capture.snapshot(), capture2.snapshot(), "Every output must receive identical messages and timestamps")

        // The app's independent-device architecture: shared launch, different tempos,
        // and stopping one endpoint must leave the other endpoint clocking.
        let secondEngine = try MIDIClockEngine()
        let firstOffset = capture.snapshot().count
        let secondOffset = capture2.snapshot().count
        let sharedStart = MIDIClockEngine.batchDeadline()
        try engine.start(outputs: [output], bpm: 120, scheduledAt: sharedStart)
        try secondEngine.start(outputs: [output2], bpm: 60, scheduledAt: sharedStart)
        Thread.sleep(forTimeInterval: 0.35)
        try engine.stop()
        Thread.sleep(forTimeInterval: 0.04)
        let stoppedCount = capture.snapshot().count
        let stillRunningCount = capture2.snapshot().count
        Thread.sleep(forTimeInterval: 0.12)
        XCTAssertEqual(capture.snapshot().count, stoppedCount)
        XCTAssertGreaterThan(capture2.snapshot().count, stillRunningCount)
        secondEngine.shutdown()
        Thread.sleep(forTimeInterval: 0.04)
        let independentFirst = Array(capture.snapshot().dropFirst(firstOffset))
        let independentSecond = Array(capture2.snapshot().dropFirst(secondOffset))
        XCTAssertEqual(independentFirst.first?.time, independentSecond.first?.time)
        for (events, bpm) in [(independentFirst, 120.0), (independentSecond, 60.0)] {
            XCTAssertEqual(events.first?.status, 0xFA)
            XCTAssertEqual(events.last?.status, 0xFC)
            let pulses = events.filter { $0.status == 0xF8 }
            let gaps = zip(pulses, pulses.dropFirst()).map { (Double($1.time) - Double($0.time)) / frequency }
            XCTAssertTrue(gaps.contains { abs($0 - 60 / (bpm * 24)) < 0.00001 })
        }

        // Resume two independent engines together after their Stop queues have drained.
        engine.drainPendingStop()
        secondEngine.drainPendingStop()
        let resumeOffset = capture.snapshot().count
        let resumeOffset2 = capture2.snapshot().count
        let sharedResume = MIDIClockEngine.batchDeadline()
        try engine.resume(outputs: [output], bpm: 180, scheduledAt: sharedResume)
        try secondEngine.resume(outputs: [output2], bpm: 180, scheduledAt: sharedResume)
        Thread.sleep(forTimeInterval: 0.15)
        let sharedStop = MIDIClockEngine.batchDeadline()
        try engine.scheduleStop(at: sharedStop)
        try secondEngine.scheduleStop(at: sharedStop)
        engine.shutdown()
        secondEngine.shutdown()
        Thread.sleep(forTimeInterval: 0.04)
        let resumed = Array(capture.snapshot().dropFirst(resumeOffset))
        let resumed2 = Array(capture2.snapshot().dropFirst(resumeOffset2))
        XCTAssertEqual(resumed.first?.status, 0xFB)
        XCTAssertEqual(resumed2.first?.status, 0xFB)
        XCTAssertEqual(resumed.first?.time, resumed2.first?.time)
        XCTAssertEqual(resumed.last?.time, resumed2.last?.time)
        for events in [resumed, resumed2] {
            XCTAssertEqual(events.last?.status, 0xFC)
            XCTAssertFalse(events.contains { $0.status == 0xFA })
            let ticks = events.filter { $0.status == 0xF8 }
            XCTAssertGreaterThan(ticks.count, 5)
            XCTAssertEqual((Double(try XCTUnwrap(ticks.first).time) - Double(try XCTUnwrap(events.first).time)) / frequency,
                           0.001, accuracy: 0.00001)
            for (a, b) in zip(ticks, ticks.dropFirst()) {
                XCTAssertGreaterThanOrEqual(Double(b.time - a.time) / frequency, 60 / (180 * 24) - 0.00001)
            }
        }
    }
}

private final class Capture: @unchecked Sendable {
    struct Event: Equatable { let status: UInt8; let time: UInt64 }
    private let lock = NSLock()
    private var events: [Event] = []
    func append(status: UInt8, time: UInt64) {
        lock.lock(); defer { lock.unlock() }
        events.append(Event(status: status, time: time))
    }
    func snapshot() -> [Event] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}
