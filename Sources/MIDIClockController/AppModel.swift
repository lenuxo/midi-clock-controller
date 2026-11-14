import AppLocalization
import AppKit
import SwiftUI
import Combine
import ClockCore
import LinkBridge

// Narrow interface keeps controller behavior testable without sending to hardware.
protocol DeviceTransport: AnyObject {
    var onFailure: ((String) -> Void)? { get set }
    func start(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws
    func resume(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws
    func setBPM(_ bpm: Double)
    func scheduleBPM(_ bpm: Double, at deadline: Double)
    func setLaunchClock(_ clock: BeatClock?, quantum: Double)
    func setBeatClock(_ clock: BeatClock?, quantum: Double)
    var waitingForBeat: Bool { get }
    var lastQueuedEventTime: Double { get }
    func drainPendingStop()
    func scheduleStop(at deadline: Double) throws
    func stop() throws
    func shutdown()
}
extension DeviceTransport {
    func setLaunchClock(_ clock: BeatClock?, quantum: Double) {}
    func setBeatClock(_ clock: BeatClock?, quantum: Double) {}
    var waitingForBeat: Bool { false }
    var lastQueuedEventTime: Double { 0 }
}
extension MIDIClockEngine: DeviceTransport {}

protocol MIDIDiscovery: AnyObject {
    var onSetupChange: (() -> Void)? { get set }
    func outputs() -> [MIDIOutput]
    func shutdown()
}
extension MIDIClockEngine: MIDIDiscovery {}

enum PlaybackAction {
    case start, resume, stop

    init(running: Bool, canContinue: Bool) {
        self = running ? .stop : canContinue ? .resume : .start
    }
}

@MainActor
final class DeviceControl: ObservableObject, Identifiable {
    let id: Int32
    @Published private(set) var output: MIDIOutput
    @Published var followsMaster = true
    @Published var startsWithMaster = false
    @Published private(set) var online = true
    @Published private(set) var running = false
    @Published private(set) var canContinue = false
    @Published private(set) var bpm: Double
    @Published private(set) var bpmText: String
    @Published var error: String?
    private var engine: DeviceTransport?
    private var beatClock: BeatClock?
    private var launchQuantum = 1.0
    var waitingForBeat: Bool { engine?.waitingForBeat ?? false }

    func setBeatClock(_ clock: BeatClock?, quantum: Double = 1) {
        beatClock = clock
        launchQuantum = quantum
        engine?.setBeatClock(clock, quantum: quantum)
    }
    private let factory: () throws -> DeviceTransport
    private let defaults: UserDefaults

    init(output: MIDIOutput, defaults: UserDefaults, factory: @escaping () throws -> DeviceTransport) {
        self.output = output
        id = output.id
        self.defaults = defaults
        self.factory = factory
        let saved = defaults.object(forKey: "deviceBPM.\(output.id)") as? Double
            ?? defaults.object(forKey: "bpm") as? Double ?? 120
        bpm = ClockSchedule.clamp(saved)
        bpmText = String(format: "%.1f", ClockSchedule.clamp(saved))
    }

    var playbackAction: PlaybackAction { PlaybackAction(running: running, canContinue: canContinue) }

    func performPlaybackAction() {
        guard online else { return }
        switch playbackAction {
        case .start: start()
        case .resume: resume()
        case .stop: stop()
        }
    }

    static func parseBPM(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, ClockSchedule.bpmRange.contains(value) else { return nil }
        return (value * 10).rounded() / 10
    }

    @discardableResult
    func commitBPM(_ text: String) -> Bool {
        guard let value = Self.parseBPM(text) else {
            error = L("请输入 20–300 之间的 BPM。")
            return false
        }
        setBPM(value)
        return true
    }

    func setBPM(_ value: Double, at deadline: Double? = nil) {
        bpm = (ClockSchedule.clamp(value) * 10).rounded() / 10
        bpmText = String(format: "%.1f", bpm)
        if let deadline { engine?.scheduleBPM(bpm, at: deadline) }
        else { engine?.setBPM(bpm) }
        defaults.set(bpm, forKey: "deviceBPM.\(id)")
        error = nil
    }

    @discardableResult
    func prepare() -> Bool {
        do {
            if engine == nil {
                let created = try factory()
                created.onFailure = { [weak self] message in
                    self?.running = false
                    self?.canContinue = false
                    self?.error = message
                }
                created.setBeatClock(beatClock, quantum: launchQuantum)
                engine = created
            }
            if !running { engine?.drainPendingStop() }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func start(at deadline: Double? = nil, launchClock: BeatClock? = nil, quantum: Double = 1) {
        begin(at: deadline, continuing: false, launchClock: launchClock, quantum: quantum)
    }

    func resume(at deadline: Double? = nil, launchClock: BeatClock? = nil, quantum: Double = 1) {
        guard canContinue else { return }
        begin(at: deadline, continuing: true, launchClock: launchClock, quantum: quantum)
    }

    private func begin(at deadline: Double?, continuing: Bool, launchClock: BeatClock?, quantum: Double) {
        guard online, !running, prepare() else { return }
        engine?.setLaunchClock(launchClock, quantum: quantum)
        do {
            if continuing { try engine?.resume(outputs: [output], bpm: bpm, scheduledAt: deadline) }
            else { try engine?.start(outputs: [output], bpm: bpm, scheduledAt: deadline) }
            running = true
            error = nil
        } catch { canContinue = false; self.error = error.localizedDescription }
    }

    func stop(at deadline: Double? = nil) {
        guard running else { return }
        let wasWaiting = waitingForBeat
        do {
            if let deadline { try engine?.scheduleStop(at: deadline) }
            else { try engine?.stop() }
            canContinue = !wasWaiting
        } catch { canContinue = false; self.error = error.localizedDescription }
        running = false
    }

    func update(output replacement: MIDIOutput?) {
        guard let replacement else {
            guard online else { return }
            stop()
            canContinue = false
            online = false
            error = L("设备已断开；其他设备继续播放。")
            return
        }
        if !online || output.endpoint != replacement.endpoint {
            stop()
            canContinue = false
            error = nil
        }
        output = replacement
        online = true
    }

    var lastQueuedEventTime: Double { engine?.lastQueuedEventTime ?? 0 }
    func drainPendingStop() { engine?.drainPendingStop() }

    func shutdown() { stop(); engine?.shutdown() }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var devices: [DeviceControl] = []
    @Published private(set) var masterBPM = 120.0
    @Published private(set) var masterBPMText = "120.0"
    @Published private var linkTransportRunning = false
    var masterRunning: Bool {
        followers.contains(where: \.running) || !independentWaitingDevices.isEmpty || (linkEnabled && followers.isEmpty && linkTransportRunning)
    }
    @Published var notice: String?
    @Published var error: String?
    @Published private(set) var linkEnabled = false
    @Published private(set) var linkPeers = 0
    @Published private(set) var linkStartStopSync = false
    @Published private(set) var linkWaiting = false
    @Published private(set) var linkSessionBPM = 120.0
    @Published private(set) var linkTempoScale = 1.0
    @Published private(set) var linkQuantum = 1
    private var linkSession: LinkControlling?
    private let linkFactory: (Double) -> LinkControlling?
    private var linkPoll: AnyCancellable?
    private var lastLinkTransport: (playing: Bool, revision: UInt64)?
    private var localLinkCommand: (playing: Bool, time: Double)?
    private var reconcileLocalLinkTransport = false
    private var discovery: MIDIDiscovery?
    private let discoveryFactory: (() throws -> MIDIDiscovery)?
    private var subscriptions: [Int32: AnyCancellable] = [:]
    private var sleepObserver: NSObjectProtocol?
    private var disconnectedRemovals: [Int32: (token: UUID, cancel: () -> Void)] = [:]
    private let scheduleRemoval: (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void

    private static func scheduleAfter(_ seconds: TimeInterval, action: @escaping @MainActor () -> Void) -> () -> Void {
        let task = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }
    private let defaults: UserDefaults
    private let factory: () throws -> DeviceTransport

    init(defaults: UserDefaults = .standard, discover: Bool = true,
         discoveryFactory: @escaping () throws -> MIDIDiscovery = { try MIDIClockEngine() },
         linkFactory: @escaping (Double) -> LinkControlling? = { LinkSession(bpm: $0) },
         scheduleRemoval: ((TimeInterval, @escaping @MainActor () -> Void) -> () -> Void)? = nil,
         factory: @escaping () throws -> DeviceTransport = { try MIDIClockEngine() }) {
        self.discoveryFactory = discover ? discoveryFactory : nil
        self.defaults = defaults
        self.linkFactory = linkFactory
        self.factory = factory
        self.scheduleRemoval = scheduleRemoval ?? Self.scheduleAfter
        masterBPM = ClockSchedule.clamp(defaults.object(forKey: "bpm") as? Double ?? 120)
        masterBPMText = String(format: "%.1f", masterBPM)
        guard discover else { return }
        refreshOutputs()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopAll()
                self?.notice = L("电脑即将休眠，所有设备已停止。唤醒后请手动开始。")
            }
        }
    }

    var onlineDevices: [DeviceControl] { devices.filter(\.online) }
    var followers: [DeviceControl] { onlineDevices.filter(\.followsMaster) }
    var independentCount: Int { onlineDevices.filter { !$0.followsMaster }.count }
    var playingCount: Int { devices.filter { $0.running && !$0.waitingForBeat }.count }
    var pendingFollowers: [DeviceControl] { followers.filter { !$0.running } }

    var independentStartTargets: [DeviceControl] {
        onlineDevices.filter { !$0.followsMaster && $0.startsWithMaster && !$0.running }
    }
    private var independentWaitingDevices: [DeviceControl] {
        onlineDevices.filter { !$0.followsMaster && $0.running && $0.waitingForBeat }
    }
    var canStartMaster: Bool { !followers.isEmpty || !independentStartTargets.isEmpty || linkEnabled }

    var resumableFollowers: [DeviceControl] { pendingFollowers.filter(\.canContinue) }
    var playbackAction: PlaybackAction {
        PlaybackAction(running: masterRunning, canContinue: !resumableFollowers.isEmpty)
    }

    func performPlaybackAction() {
        switch playbackAction {
        case .start: startMaster()
        case .resume: continueMaster()
        case .stop: stopMaster()
        }
    }

    func setFollowing(_ device: DeviceControl, _ following: Bool) {
        guard device.followsMaster != following else { return }
        let wasRunning = masterRunning
        device.followsMaster = following
        device.setBeatClock(following && linkEnabled ? linkSession : nil, quantum: Double(linkQuantum))
        notice = nil
        // Detaching preserves its current tempo and transport, without interrupting sound.
        guard following else { device.setBPM(device.bpm); return }
        device.setBPM(masterBPM)
        if wasRunning { device.start(at: MIDIClockEngine.batchDeadline()) }
        else { device.stop() }
    }

    @discardableResult
    func commitMasterBPM(_ text: String) -> Bool {
        guard let value = DeviceControl.parseBPM(text) else {
            error = L("主控 BPM 请输入 20–300 之间的数值。")
            return false
        }
        if !linkEnabled || abs(value - masterBPM) > 0.051 { setMasterBPM(value) }
        error = nil
        return true
    }

    func setMasterBPM(_ value: Double) {
        if linkEnabled, let linkSession {
            let bpm = (ClockSchedule.clamp(value) * 10).rounded() / 10
            // A folded MIDI tempo edits the session in the same ratio.
            var sessionBPM = bpm / linkTempoScale
            if abs(sessionBPM * LinkSession.tempoScale(for: sessionBPM) - bpm) > 0.001 {
                sessionBPM = bpm // An explicit edit across ratio ranges returns to 1:1.
            }
            linkSession.setTempo(sessionBPM, at: LinkSession.hostTime() + 0.050)
            adoptLinkState(linkSession.state(at: LinkSession.hostTime() + 0.050))
            return
        }
        masterBPM = (ClockSchedule.clamp(value) * 10).rounded() / 10
        masterBPMText = String(format: "%.1f", masterBPM)
        let deadline = MIDIClockEngine.batchDeadline()
        followers.forEach { $0.setBPM(masterBPM, at: deadline) }
        defaults.set(masterBPM, forKey: "bpm")
        error = nil
    }

    func setLinkEnabled(_ enabled: Bool) {
        guard enabled != linkEnabled else { return }
        guard playbackAction != .stop else {
            error = L("请先停止主控，再切换 Link。"); return
        }
        if enabled {
            guard let session = linkFactory(masterBPM), session.setEnabled(true) else {
                error = L("无法启用 Link，请检查本地网络权限。"); return
            }
            linkSession = session
            linkTransportRunning = false
            linkEnabled = true
            linkStartStopSync = false
            session.setTransportSync(false)
            let state = session.state(at: LinkSession.hostTime())
            lastLinkTransport = (state.playing, state.transportRevision)
            adoptLinkState(state)
            devices.filter(\.followsMaster).forEach { $0.setBeatClock(session, quantum: Double(linkQuantum)) }
            linkPoll = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.pollLink() }
        } else {
            linkPoll?.cancel(); linkPoll = nil
            setLinkStartStopSync(false)
            devices.filter(\.followsMaster).forEach { $0.setBeatClock(nil) }
            _ = linkSession?.setEnabled(false)
            linkSession = nil
            linkEnabled = false
            linkPeers = 0
            linkWaiting = false
        }
        error = nil
    }

    func setLinkStartStopSync(_ enabled: Bool) {
        let value = enabled && linkEnabled
        // Capture a baseline: enabling sync never consumes an old Play command.
        if let session = linkSession {
            let state = session.state(at: LinkSession.hostTime())
            lastLinkTransport = (state.playing, state.transportRevision)
            reconcileLocalLinkTransport = false
            localLinkCommand = nil
            session.setTransportSync(value)
        }
        linkStartStopSync = value
    }

    func setLinkQuantum(_ beats: Int) {
        guard !masterRunning else { return }
        linkQuantum = beats == 4 ? 4 : 1
        if linkEnabled { devices.filter(\.followsMaster).forEach { $0.setBeatClock(linkSession, quantum: Double(linkQuantum)) } }
    }

    private func adoptLinkState(_ state: LinkState) {
        guard state.timeline.valid else { error = L("Link 时间线不可用"); return }
        linkPeers = state.peers
        linkSessionBPM = state.sessionBPM
        linkTempoScale = state.tempoScale
        if abs(masterBPM - state.timeline.bpm) > 0.000001 {
            masterBPM = state.timeline.bpm
            masterBPMText = String(format: "%.1f", masterBPM)
            followers.forEach { $0.setBPM(masterBPM) }
            defaults.set(masterBPM, forKey: "bpm")
        }
    }

    private func publishLinkTransport(_ playing: Bool) {
        guard linkEnabled, linkStartStopSync, let session = linkSession else { return }
        let baseline = session.state(at: LinkSession.hostTime())
        // Record our intention before committing. A subsequent remote reversal
        // must be observed, not consumed as the acknowledgement of our command.
        lastLinkTransport = (playing, baseline.transportRevision)
        reconcileLocalLinkTransport = true
        let time = LinkSession.hostTime()
        localLinkCommand = (playing, time)
        session.setPlaying(playing, at: time)
    }

    private func updateLinkWaiting() { linkWaiting = followers.contains(where: \.waitingForBeat) || !independentWaitingDevices.isEmpty }

    /// UI polling observes transport; MIDI pulses use fresh snapshots on their own queues.
    func pollLink() {
        guard linkEnabled, let session = linkSession else { return }
        let state = session.state(at: LinkSession.hostTime())
        adoptLinkState(state)
        updateLinkWaiting()
        if !followers.isEmpty && !followers.contains(where: \.running) { linkTransportRunning = false }
        guard let previous = lastLinkTransport else { return }
        let count = state.transportRevision &- previous.revision
        // A local Play/Stop pair can both be committed before the SDK reports
        // either callback. Its microsecond timestamp identifies our own write
        // only for echo suppression; timeline remapping never triggers playback.
        if let command = localLinkCommand, command.playing == state.playing,
           abs(command.time - state.transportTime) <= 0.00000051 {
            lastLinkTransport = (command.playing, state.transportRevision)
            reconcileLocalLinkTransport = false
            return
        }
        localLinkCommand = nil
        var playing = previous.playing
        // The bridge increments only when the callback value changes. The
        // revision delta and final callback value encode the whole alternating
        // sequence, even when the current session snapshot is ahead of callbacks.
        for remaining in (0..<count).reversed() {
            let command = remaining.isMultiple(of: 2) ? state.callbackPlaying : !state.callbackPlaying
            if linkStartStopSync && playing != command { applyRemoteTransport(command) }
            playing = command
        }
        if reconcileLocalLinkTransport && state.playing != playing {
            if linkStartStopSync { applyRemoteTransport(state.playing) }
            playing = state.playing
        }
        lastLinkTransport = (playing, state.transportRevision)
        reconcileLocalLinkTransport = false
    }

    private func applyRemoteTransport(_ playing: Bool) {
        if playing {
            // Link has no Continue message: preserve eligible local positions, start the rest.
            launchDevices(pendingFollowers + independentStartTargets, continuing: true)
            linkTransportRunning = followers.contains(where: \.running) || followers.isEmpty
            updateLinkWaiting()
        } else {
            let deadline = MIDIClockEngine.batchDeadline()
            (followers + independentWaitingDevices).forEach { $0.stop(at: deadline) }
            linkTransportRunning = false
            linkWaiting = false
        }
    }

    func refreshOutputs() {
        guard let discoveryFactory else { return }
        do {
            if discovery == nil {
                let client = try discoveryFactory()
                client.onSetupChange = { [weak self] in self?.refreshOutputs() }
                discovery = client
                error = nil
            }
            if let discovery { reconcile(discovery.outputs()) }
        } catch { self.error = error.localizedDescription }
    }

    func reconcile(_ outputs: [MIDIOutput]) {
        for device in devices {
            device.update(output: outputs.first { $0.id == device.id })
            if device.online {
                disconnectedRemovals.removeValue(forKey: device.id)?.cancel()
            } else if disconnectedRemovals[device.id] == nil {
                let id = device.id
                let token = UUID()
                let cancel = scheduleRemoval(30) { [weak self] in
                    self?.removeDisconnectedDevice(id: id, token: token)
                }
                disconnectedRemovals[id] = (token, cancel)
            }
        }
        for output in outputs where !devices.contains(where: { $0.id == output.id }) {
            let device = DeviceControl(output: output, defaults: defaults, factory: factory)
            device.setBPM(masterBPM)
            device.setBeatClock(linkEnabled ? linkSession : nil, quantum: Double(linkQuantum))
            devices.append(device)
            subscriptions[output.id] = device.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
        // Reconnected followers adopt the tempo, but never unexpectedly start playing.
        followers.forEach { if $0.bpm != masterBPM { $0.setBPM(masterBPM) } }
    }

    private func removeDisconnectedDevice(id: Int32, token: UUID) {
        // A cancelled callback may already be queued. Never let an old disconnect
        // remove a reconnected device or one in a new 30-second grace period.
        guard disconnectedRemovals[id]?.token == token,
              let device = devices.first(where: { $0.id == id }), !device.online else { return }
        disconnectedRemovals.removeValue(forKey: id)?.cancel()
        device.shutdown()
        subscriptions.removeValue(forKey: id)?.cancel()
        devices.removeAll { $0.id == id }
    }

    private func launchDevices(_ targets: [DeviceControl], continuing: Bool) {
        let ready = targets.filter { $0.prepare() }
        let deadline = MIDIClockEngine.batchDeadline()
        for device in ready {
            let clock = !device.followsMaster && linkEnabled ? linkSession : nil
            if continuing && device.canContinue {
                device.resume(at: deadline, launchClock: clock, quantum: Double(linkQuantum))
            } else {
                device.start(at: deadline, launchClock: clock, quantum: Double(linkQuantum))
            }
        }
    }

    func startMaster() {
        guard canStartMaster else { return }
        let targets = pendingFollowers + independentStartTargets
        launchDevices(targets, continuing: false)
        linkTransportRunning = linkEnabled && (followers.isEmpty || followers.contains(where: \.running))
        publishLinkTransport(true)
        updateLinkWaiting()
        notice = targets.allSatisfy(\.running) ? nil : L("部分设备未能开始，请查看设备卡片中的提示。")
    }

    func continueMaster() {
        let targets = resumableFollowers + independentStartTargets
        guard !targets.isEmpty else { return }
        launchDevices(targets, continuing: true)
        linkTransportRunning = linkEnabled && (followers.isEmpty || followers.contains(where: \.running))
        publishLinkTransport(true)
        updateLinkWaiting()
        notice = targets.allSatisfy(\.running) && pendingFollowers.isEmpty ? nil
            : L("部分设备无法继续；请查看设备提示，或停止后从头开始。")
    }

    func stopMaster() {
        publishLinkTransport(false)
        let deadline = MIDIClockEngine.batchDeadline()
        (followers + independentWaitingDevices).forEach { $0.stop(at: deadline) }
        linkTransportRunning = false
        linkWaiting = false
        notice = nil
    }

    func stopAll() {
        // Emergency stop stays local, and cannot be undone by a later remote Play.
        setLinkStartStopSync(false)
        linkWaiting = false
        // Short emergency action, regardless of current selection.
        let latestEvent = devices.map(\.lastQueuedEventTime).max() ?? 0
        let deadline = max(latestEvent + 0.001, MIDIClockEngine.emergencyStopDeadline())
        devices.forEach { $0.stop(at: deadline) }
        devices.forEach { $0.drainPendingStop() }
        linkTransportRunning = false
        notice = linkEnabled ? L("本机 MIDI 已全部停止；Link 启停联动已关闭。") : L("所有设备已停止。")
    }

    func shutdown() {
        disconnectedRemovals.values.forEach { $0.cancel() }
        disconnectedRemovals.removeAll()
        linkPoll?.cancel()
        linkPoll = nil
        devices.forEach { $0.shutdown() }
        _ = linkSession?.setEnabled(false)
        linkSession = nil
        discovery?.shutdown()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }
}
