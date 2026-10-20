import AppLocalization
import AppKit
import SwiftUI
import Combine
import ClockCore

// Narrow interface keeps controller behavior testable without sending to hardware.
protocol DeviceTransport: AnyObject {
    var onFailure: ((String) -> Void)? { get set }
    func start(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws
    func resume(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws
    func setBPM(_ bpm: Double)
    func scheduleBPM(_ bpm: Double, at deadline: Double)
    func drainPendingStop()
    func scheduleStop(at deadline: Double) throws
    func stop() throws
    func shutdown()
}
extension MIDIClockEngine: DeviceTransport {}

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
    @Published private(set) var online = true
    @Published private(set) var running = false
    @Published private(set) var canContinue = false
    @Published private(set) var bpm: Double
    @Published var bpmText: String
    @Published var error: String?
    private var engine: DeviceTransport?
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
    func commitBPM() -> Bool {
        guard let value = Self.parseBPM(bpmText) else {
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
                engine = created
            }
            if !running { engine?.drainPendingStop() }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func start(at deadline: Double? = nil) {
        begin(at: deadline, continuing: false)
    }

    func resume(at deadline: Double? = nil) {
        guard canContinue else { return }
        begin(at: deadline, continuing: true)
    }

    private func begin(at deadline: Double?, continuing: Bool) {
        guard online, !running, commitBPM(), prepare() else { return }
        do {
            if continuing { try engine?.resume(outputs: [output], bpm: bpm, scheduledAt: deadline) }
            else { try engine?.start(outputs: [output], bpm: bpm, scheduledAt: deadline) }
            running = true
            error = nil
        } catch { canContinue = false; self.error = error.localizedDescription }
    }

    func stop(at deadline: Double? = nil) {
        guard running else { return }
        do {
            if let deadline { try engine?.scheduleStop(at: deadline) }
            else { try engine?.stop() }
            canContinue = true
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

    func shutdown() { stop(); engine?.shutdown() }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var devices: [DeviceControl] = []
    @Published private(set) var masterBPM = 120.0
    @Published var masterBPMText = "120.0"
    @Published private(set) var masterRunning = false
    @Published var notice: String?
    @Published var error: String?
    private var discovery: MIDIClockEngine?
    private var subscriptions: [Int32: AnyCancellable] = [:]
    private var sleepObserver: NSObjectProtocol?
    private let defaults: UserDefaults
    private let factory: () throws -> DeviceTransport

    init(defaults: UserDefaults = .standard, discover: Bool = true,
         factory: @escaping () throws -> DeviceTransport = { try MIDIClockEngine() }) {
        self.defaults = defaults
        self.factory = factory
        masterBPM = ClockSchedule.clamp(defaults.object(forKey: "bpm") as? Double ?? 120)
        masterBPMText = String(format: "%.1f", masterBPM)
        guard discover else { return }
        do {
            let discovery = try MIDIClockEngine()
            self.discovery = discovery
            discovery.onSetupChange = { [weak self] in self?.refreshOutputs() }
            refreshOutputs()
        } catch { self.error = error.localizedDescription }
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
    var playingCount: Int { devices.filter(\.running).count }
    var pendingFollowers: [DeviceControl] { followers.filter { !$0.running } }

    var resumableFollowers: [DeviceControl] { pendingFollowers.filter(\.canContinue) }
    var playbackAction: PlaybackAction {
        PlaybackAction(running: followers.contains(where: \.running), canContinue: !resumableFollowers.isEmpty)
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
        device.followsMaster = following
        notice = nil
        // Detaching preserves its current tempo and transport, without interrupting sound.
        guard following else { device.setBPM(device.bpm); return }
        device.setBPM(masterBPM)
        if masterRunning { device.start(at: MIDIClockEngine.batchDeadline()) }
        else { device.stop() }
    }

    @discardableResult
    func commitMasterBPM() -> Bool {
        guard let value = DeviceControl.parseBPM(masterBPMText) else {
            error = L("主控 BPM 请输入 20–300 之间的数值。")
            return false
        }
        setMasterBPM(value)
        return true
    }

    func setMasterBPM(_ value: Double) {
        masterBPM = (ClockSchedule.clamp(value) * 10).rounded() / 10
        masterBPMText = String(format: "%.1f", masterBPM)
        let deadline = MIDIClockEngine.batchDeadline()
        followers.forEach { $0.setBPM(masterBPM, at: deadline) }
        defaults.set(masterBPM, forKey: "bpm")
        error = nil
    }

    func refreshOutputs() { reconcile(discovery?.outputs() ?? []) }

    func reconcile(_ outputs: [MIDIOutput]) {
        for device in devices {
            device.update(output: outputs.first { $0.id == device.id })

        }
        for output in outputs where !devices.contains(where: { $0.id == output.id }) {
            let device = DeviceControl(output: output, defaults: defaults, factory: factory)
            device.setBPM(masterBPM)
            devices.append(device)
            subscriptions[output.id] = device.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
        // Reconnected followers adopt the tempo, but never unexpectedly start playing.
        followers.forEach { if $0.bpm != masterBPM { $0.setBPM(masterBPM) } }
    }

    func startMaster() {
        guard !followers.isEmpty, commitMasterBPM() else { return }
        pendingFollowers.forEach { _ = $0.prepare() }
        let deadline = MIDIClockEngine.batchDeadline()
        pendingFollowers.forEach { $0.start(at: deadline) }
        masterRunning = followers.contains(where: \.running)
        notice = pendingFollowers.isEmpty ? nil : L("部分跟随设备未能开始，请查看设备行中的提示。")
    }

    func continueMaster() {
        let targets = pendingFollowers.filter(\.canContinue)
        guard !targets.isEmpty, commitMasterBPM() else { return }
        targets.forEach { _ = $0.prepare() }
        let deadline = MIDIClockEngine.batchDeadline()
        targets.forEach { $0.resume(at: deadline) }
        masterRunning = followers.contains(where: \.running)
        notice = pendingFollowers.isEmpty ? nil : L("部分设备无法继续；请查看设备提示，或停止后从头开始。")
    }

    func stopMaster() {
        let deadline = MIDIClockEngine.batchDeadline()
        followers.forEach { $0.stop(at: deadline) }
        masterRunning = false
        notice = nil
    }

    func stopAll() {
        // Short emergency action, regardless of current selection.
        devices.forEach { $0.stop() }
        masterRunning = false
        notice = L("所有设备已停止。")
    }

    func shutdown() {
        devices.forEach { $0.shutdown() }
        discovery?.shutdown()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }
}
