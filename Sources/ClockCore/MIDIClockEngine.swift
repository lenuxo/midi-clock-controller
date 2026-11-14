import AppLocalization
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
    public var errorDescription: String? { L("%1$@失败（CoreMIDI %2$@）。", String(operation), String(status)) }
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
    private var beatClock: BeatClock?
    private var launchClock: BeatClock?
    private var launchQuantum = 1.0
    private var externalBeatScale = 1.0
    private var nextExternalBeat: Double?
    private var pendingExternalTransport: UInt8?
    private var lastExternalClock: Double?
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
    private static let schedulingHorizon = 0.008
    private var lookAhead: Double { Self.schedulingHorizon }
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
        }, L("初始化 MIDI"))
        do {
            try check(MIDIOutputPortCreate(client, "Clock output" as CFString, &port), L("创建 MIDI 输出"))
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
                              name: name?.takeRetainedValue() as String? ?? L("MIDI 输出 %1$@", String(uniqueID)))
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
            guard !unique.isEmpty else { throw MIDIError(operation: L("请选择至少一个 MIDI 输出；启动"), status: -50) }
            generation &+= 1
            let run = generation
            destinations = unique
            let start = max(now() + lookAhead, transportBoundary + 0.001, scheduledAt ?? 0)
            lastSubmitted = start
            schedule = ClockSchedule(bpm: bpm, start: start + 0.001, preserveGrid: scheduledAt != nil)
            if let source = beatClock ?? launchClock {
                let timeline = source.timeline(at: now())
                guard timeline.valid else { schedule = nil; throw MIDIError(operation: L("Link 时间线不可用"), status: -1) }
                externalBeatScale = timeline.beatScale
                nextExternalBeat = ceil(timeline.beat(at: start + 0.001) / launchQuantum) * launchQuantum
                pendingExternalTransport = status
                lastExternalClock = nil
                lastSubmitted = 0 // Nothing has been submitted while waiting for the boundary.
            }
            do { if pendingExternalTransport == nil { try send(status, at: start) } }
            catch {
                // Some outputs may have accepted Start or Continue. Stop all before reporting failure.
                try? stopOnQueue()
                throw error
            }
            guard automaticTimer else { return }
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                              reason: L("正在发送 MIDI 同步时钟"))
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
        serialized { pendingTempo = nil; if beatClock == nil { schedule?.setBPM(bpm) } }
    }

    /// Use this source only for the next launch boundary, then keep the local BPM.
    public func setLaunchClock(_ clock: BeatClock?, quantum: Double = 1) {
        serialized {
            guard schedule == nil, beatClock == nil else { return }
            launchClock = clock
            launchQuantum = quantum == 4 ? 4 : 1
        }
    }

    public func setBeatClock(_ clock: BeatClock?, quantum: Double = 1) {
        serialized {
            // AppModel only changes the master source while followers are stopped.
            // A running device may detach without restarting or losing its next tick.
            if clock == nil, let source = beatClock, schedule != nil, let next = nextExternalBeat {
                let snapshot = source.timeline(at: now())
                if snapshot.valid {
                    schedule = ClockSchedule(bpm: snapshot.bpm, start: max(now(), snapshot.time(at: next), lastSubmitted + snapshot.secondsPerBeat / 24))
                }
                // If detached during a quantized launch, retain the armed Start/Continue
                // and send it immediately before the first local tick in pump().
            }
            beatClock = clock
            launchQuantum = quantum == 4 ? 4 : 1
            if clock != nil, schedule != nil, nextExternalBeat == nil, let snapshot = clock?.timeline(at: now()), snapshot.valid {
                externalBeatScale = snapshot.beatScale
                let spacing = max(schedule?.interval ?? 0, snapshot.secondsPerBeat / 24)
                nextExternalBeat = ceil(snapshot.beat(at: max(now() + lookAhead, lastSubmitted + spacing)) * 24) / 24
            }
            if clock != nil, schedule != nil, nextExternalBeat == nil {
                fail(L("Link 时间线不可用"))
            }
            if clock == nil { nextExternalBeat = nil; lastExternalClock = nil }
        }
    }

    public var waitingForBeat: Bool { serialized { pendingExternalTransport != nil } }

    public func scheduleBPM(_ bpm: Double, at deadline: Double) {
        serialized { if schedule != nil, beatClock == nil { pendingTempo = (ClockSchedule.clamp(bpm), deadline) } }
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

    public var lastQueuedEventTime: Double { serialized { schedule == nil ? 0 : lastSubmitted } }

    /// The scheduling horizon plus the guard after the last queued pulse.
    public static func emergencyStopDeadline() -> Double {
        Double(AudioGetCurrentHostTime()) / AudioGetHostClockFrequency() + schedulingHorizon + 0.001
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
        nextExternalBeat = nil
        lastExternalClock = nil
        let wasArmed = pendingExternalTransport != nil
        pendingExternalTransport = nil
        launchClock = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        if wasArmed { destinations = []; return }
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
        if let source = beatClock ?? launchClock, schedule != nil {
            pumpExternal(source)
            return
        }
        guard var current = schedule else { return }
        let time = now()
        if let status = pendingExternalTransport {
            // Detaching an armed Link device uses a local, bounded launch instead.
            current = ClockSchedule(bpm: current.bpm, start: time + 0.002)
            do { try send(status, at: time + 0.001) }
            catch { fail(error.localizedDescription); return }
            lastSubmitted = time + 0.001
            pendingExternalTransport = nil
        }
        // A stalled host must not burst old clocks into a musical device.
        if current.next < time - min(0.050, current.interval) {
            fail(L("时钟调度中断，已停止。请重新开始。"))
            return
        }
        // Apply the local or group late-wake policy before submitting this tick.
        current.delayNext(until: time)
        do {
            while current.next <= time + lookAhead {
                if let change = pendingTempo, current.gridTime >= change.time {
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

    private func pumpExternal(_ source: BeatClock) {
        guard var beat = nextExternalBeat else { return }
        let time = now()
        let timeline = source.timeline(at: time)
        guard timeline.valid else { fail(L("Link 时间线不可用")); return }
        let interval = timeline.secondsPerBeat / 24
        if timeline.beatScale != externalBeatScale {
            let quantum = pendingExternalTransport == nil ? 1.0 / 24 : launchQuantum
            beat = ceil(timeline.beat(at: max(time + lookAhead, lastSubmitted + interval)) / quantum) * quantum
            externalBeatScale = timeline.beatScale
        }
        var deadline = timeline.time(at: beat)
        if pendingExternalTransport == nil, let lastExternalClock,
           deadline - lastExternalClock > interval * 2.5 + lookAhead {
            fail(L("Link 拍点发生跳变，已停止。请重新开始。")); return
        }
        do {
            if let status = pendingExternalTransport {
                if deadline < time + 0.001 {
                    // A tempo/phase change can move an armed boundary into the past.
                    // Re-arm at a future boundary; never catch up old transport messages.
                    beat = ceil(timeline.beat(at: time + lookAhead) / launchQuantum) * launchQuantum
                    deadline = timeline.time(at: beat)
                }
                nextExternalBeat = beat
                guard deadline - 0.001 <= time + lookAhead else { return }
                // Mark transport submitted before fan-out so partial failure still sends Stop.
                pendingExternalTransport = nil
                lastSubmitted = deadline - 0.001
                try send(status, at: deadline - 0.001)
                if beatClock == nil, launchClock != nil, let current = schedule {
                    // Keep the first pulse on the shared boundary. Subsequent
                    // pulses use this device's own tempo and absolute schedule.
                    launchClock = nil
                    nextExternalBeat = nil
                    schedule = ClockSchedule(bpm: current.bpm, start: deadline)
                    pump()
                    return
                }
            } else if deadline < time - min(0.050, interval) {
                fail(L("时钟调度中断，已停止。请重新开始。")); return
            }
            // Missing a slightly late pulse is preferable to a compressed catch-up burst.
            if deadline < time { beat += 1.0 / 24; deadline = timeline.time(at: beat) }
            var count = 0
            while deadline <= time + lookAhead {
                guard count < 8, deadline >= time,
                      lastExternalClock.map({ deadline - $0 >= interval * 0.5 }) ?? true else {
                    fail(L("Link 拍点发生跳变，已停止。请重新开始。")); return
                }
                lastSubmitted = deadline
                try send(0xF8, at: deadline)
                lastExternalClock = deadline
                beat += 1.0 / 24
                deadline = timeline.time(at: beat)
                count += 1
            }
            nextExternalBeat = beat
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
                        NSLocalizedDescriptionKey: L("%1$@：%2$@ 已停止当前时钟输出，请检查连接。", String(output.name), String(error.localizedDescription))
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
        try check(result, L("发送 MIDI"))
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw MIDIError(operation: operation, status: status) }
    }
}
