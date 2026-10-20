import Foundation
import CoreMIDI
import CoreAudio

public struct MIDIOutput: Identifiable, Equatable {
    public let id: MIDIUniqueID
    public let endpoint: MIDIEndpointRef
    public let name: String
    public init(id: MIDIUniqueID, endpoint: MIDIEndpointRef, name: String) {
        self.id = id; self.endpoint = endpoint; self.name = name
    }
}

public struct MIDIError: LocalizedError {
    public let operation: String
    public let status: OSStatus
    public var errorDescription: String? { "\(operation)失败（CoreMIDI \(status)）。" }
}

/// All transport state and output writes are confined to one serial queue.
public final class MIDIClockEngine {
    public var onSetupChange: (() -> Void)?
    public var onFailure: ((String) -> Void)?
    private let queue = DispatchQueue(label: "MIDIClock.scheduler", qos: .userInteractive)
    private var client: MIDIClientRef = 0
    private var port: MIDIPortRef = 0
    private var timer: DispatchSourceTimer?
    private var destinations: [MIDIOutput] = []
    private var schedule: ClockSchedule?
    private var pendingTempo: (bpm: Double, time: Double)?
    private var lastSubmitted: Double = 0
    private var transportBoundary: Double = 0
    private let frequency = AudioGetHostClockFrequency()
    private let queueKey = DispatchSpecificKey<Bool>()
    private var generation: UInt64 = 0
    private var clock: () -> Double = { Double(AudioGetCurrentHostTime()) / AudioGetHostClockFrequency() }
    private var wait: (Double) -> Void = { Thread.sleep(forTimeInterval: $0) }
    private var testSender: ((MIDIEndpointRef, UInt8, Double) throws -> Void)?
    private var automaticTimer = true
    private let lookAhead = 0.008
    private var activity: NSObjectProtocol?

    // Injectable host time and sink let tests reproduce scheduling stalls without wall-clock races.
    internal convenience init(clock: @escaping () -> Double, wait: @escaping (Double) -> Void,
                              sender: @escaping (UInt8, Double) throws -> Void) {
        self.init(clock: clock, wait: wait, sender: { _, status, time in try sender(status, time) })
    }

    internal init(clock: @escaping () -> Double, wait: @escaping (Double) -> Void,
                  sender: @escaping (MIDIEndpointRef, UInt8, Double) throws -> Void) {
        self.clock = clock
        self.wait = wait
        testSender = sender
        automaticTimer = false
        queue.setSpecific(key: queueKey, value: true)
    }

    public init() throws {
        queue.setSpecific(key: queueKey, value: true)
        try check(MIDIClientCreateWithBlock("MIDI Clock Controller" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.onSetupChange?() }
        }, "初始化 MIDI")
        do {
            try check(MIDIOutputPortCreate(client, "Clock output" as CFString, &port), "创建 MIDI 输出")
        } catch {
            MIDIClientDispose(client)
            client = 0
            throw error
        }
    }

    deinit {
        shutdown()
        if port != 0 { MIDIPortDispose(port) }
        if client != 0 { MIDIClientDispose(client) }
    }

    public func outputs() -> [MIDIOutput] {
        (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
            guard endpoint != 0, offline == 0 else { return nil }
            var uniqueID: Int32 = 0
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr else { return nil }
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
            return MIDIOutput(id: uniqueID, endpoint: endpoint,
                              name: name?.takeRetainedValue() as String? ?? "MIDI 输出 \(uniqueID)")
        }
    }

    public func start(output: MIDIOutput, bpm: Double) throws {
        try start(outputs: [output], bpm: bpm)
    }

    public func start(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double? = nil) throws {
        try begin(outputs: outputs, bpm: bpm, scheduledAt: scheduledAt, status: 0xFA)
    }

    public func resume(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double? = nil) throws {
        try begin(outputs: outputs, bpm: bpm, scheduledAt: scheduledAt, status: 0xFB)
    }

    private func begin(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?, status: UInt8) throws {
        try serialized {
            guard schedule == nil else { return }
            drainTransport()
            var seen = Set<MIDIEndpointRef>()
            let unique = outputs.filter { $0.endpoint != 0 && seen.insert($0.endpoint).inserted }
            guard !unique.isEmpty else { throw MIDIError(operation: "请选择至少一个 MIDI 输出；启动", status: -50) }
            generation &+= 1
            let run = generation
            destinations = unique
            let start = max(now() + lookAhead, transportBoundary + 0.001, scheduledAt ?? 0)
            lastSubmitted = start
            schedule = ClockSchedule(bpm: bpm, start: start + 0.001)
            do { try send(status, at: start) }
            catch {
                // Some outputs may have accepted Start or Continue. Stop all before reporting failure.
                try? stopOnQueue()
                throw error
            }
            guard automaticTimer else { return }
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                              reason: "正在发送 MIDI 同步时钟")
            let source = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(200))
            source.setEventHandler { [weak self] in
                guard let self, self.generation == run else { return }
                self.pump()
            }
            timer = source
            source.resume()
        }
    }

    public func setBPM(_ bpm: Double) {
        serialized { pendingTempo = nil; schedule?.setBPM(bpm) }
    }

    public func scheduleBPM(_ bpm: Double, at deadline: Double) {
        serialized { if schedule != nil { pendingTempo = (ClockSchedule.clamp(bpm), deadline) } }
    }

    public func drainPendingStop() { serialized { drainTransport() } }

    /// Stop follows the last queued clock and waits until its timestamp is due (~9 ms).
    /// Avoid flushing the destination, which could discard another app's MIDI events.
    public func stop() throws {
        try serialized { try stopOnQueue() }
    }

    /// Shared host-clock deadline for coordinating independent device transports.
    public static func batchDeadline() -> Double {
        Double(AudioGetCurrentHostTime()) / AudioGetHostClockFrequency() + 0.050
    }

    /// Queue a group Stop without blocking other devices from receiving the same deadline.
    public func scheduleStop(at deadline: Double) throws {
        try serialized { try stopOnQueue(scheduledAt: deadline, drain: false) }
    }

    public func shutdown() {
        serialized {
            try? stopOnQueue()
            drainTransport()
        }
    }

    private func stopOnQueue(scheduledAt: Double? = nil, drain: Bool = true) throws {
        guard schedule != nil else { return }
        timer?.cancel()
        timer = nil
        schedule = nil
        pendingTempo = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        transportBoundary = max(max(now(), lastSubmitted) + 0.001, scheduledAt ?? 0)
        defer { if drain { drainTransport() }; destinations = [] }
        try send(0xFC, at: transportBoundary)
    }

    private func drainTransport() {
        // Bound each stop/start cycle instead of accumulating future transport commands.
        // Also keep the output port alive until its final Stop is due.
        while true {
            let remaining = transportBoundary - now()
            guard remaining > 0 else { return }
            wait(remaining + 0.0001)
        }
    }

    internal func pumpForTesting() { serialized { pump() } }

    private func serialized<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true { return try body() }
        return try queue.sync(execute: body)
    }

    private func pump() {
        guard var current = schedule else { return }
        let time = now()
        // A stalled host must not burst old clocks into a musical device.
        if current.next < time - min(0.050, current.interval) {
            fail("时钟调度中断，已停止。请重新开始。")
            return
        }
        // If a deadline is slightly late, shift the remaining grid by the same amount.
        // Clamping only this pulse would compress the following interval.
        current.delayNext(until: time)
        do {
            while current.next <= time + lookAhead {
                if let change = pendingTempo, current.next >= change.time {
                    current.setBPM(change.bpm)
                    pendingTempo = nil
                }
                guard let deadline = current.pop(through: time + lookAhead) else { break }
                // Track partial fan-out too: Stop must follow every accepted Clock.
                lastSubmitted = deadline
                try send(0xF8, at: deadline)
            }
            schedule = current
        } catch { fail(error.localizedDescription) }
    }

    private func fail(_ message: String) {
        let failedRun = generation
        try? stopOnQueue()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.serialized({ self.generation == failedRun }) else { return }
            self.onFailure?(message)
        }
    }

    private func now() -> Double { clock() }

    private func send(_ status: UInt8, at seconds: Double) throws {
        var firstError: Error?
        for output in destinations {
            do { try send(status, at: seconds, to: output.endpoint) }
            catch {
                if firstError == nil {
                    firstError = NSError(domain: "MIDIClock", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "\(output.name)：\(error.localizedDescription) 已停止当前时钟输出，请检查连接。"
                    ])
                }
            }
        }
        if let firstError { throw firstError }
    }

    private func send(_ status: UInt8, at seconds: Double, to destination: MIDIEndpointRef) throws {
        if let testSender { try testSender(destination, status, seconds); return }
        var events = MIDIEventList()
        // Universal MIDI Packet: System message, group 0, realtime status, zero data.
        var word = UInt32(0x10000000) | UInt32(status) << 16
        let result: OSStatus = withUnsafeMutablePointer(to: &events) { list in
            let packet = MIDIEventListInit(list, ._1_0)
            // A single 32-bit word always fits in the stack-allocated MIDIEventList.
            _ = MIDIEventListAdd(list, MemoryLayout<MIDIEventList>.size, packet,
                                 UInt64(seconds * frequency), 1, &word)
            return MIDISendEventList(port, destination, list)
        }
        try check(result, "发送 MIDI")
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw MIDIError(operation: operation, status: status) }
    }
}
