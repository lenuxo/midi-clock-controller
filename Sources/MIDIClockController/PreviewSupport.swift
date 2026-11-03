#if DEBUG
import Foundation
import ClockCore
import LinkBridge

// Dedicated UI preview bundle: no CoreMIDI client, ports, or hardware messages.
private final class PreviewTransport: DeviceTransport {
    var onFailure: ((String) -> Void)?
    private var source: BeatClock?
    private var quantum = 1.0
    private var due: Double?
    var waitingForBeat: Bool { due.map { LinkSession.hostTime() < $0 } ?? false }
    func setBeatClock(_ clock: BeatClock?, quantum: Double) { source = clock; self.quantum = quantum }
    func start(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws {
        guard let source else { due = nil; return }
        let time = LinkSession.hostTime()
        let timeline = source.timeline(at: time)
        due = timeline.time(at: ceil(timeline.beat(at: time + 0.05) / quantum) * quantum)
    }
    func resume(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws {
        try start(outputs: outputs, bpm: bpm, scheduledAt: scheduledAt)
    }
    func setBPM(_ bpm: Double) {}
    func scheduleBPM(_ bpm: Double, at deadline: Double) {}
    func drainPendingStop() {}
    func scheduleStop(at deadline: Double) throws { due = nil }
    func stop() throws { due = nil }
    func shutdown() {}
}

@MainActor func previewModel() -> AppModel {
    let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, discover: false,
                         linkFactory: { PreviewLink(bpm: ProcessInfo.processInfo.environment["MIDI_CLOCK_PREVIEW"] == "link-ratio" ? 999 : $0) }, factory: { PreviewTransport() })
    if ProcessInfo.processInfo.environment["MIDI_CLOCK_PREVIEW"] == "empty" { return model }
    model.reconcile([
        MIDIOutput(id: 1, endpoint: 1, name: "Drum Machine · USB MIDI"),
        MIDIOutput(id: 2, endpoint: 2, name: "Synthesizer · USB MIDI"),
        MIDIOutput(id: 3, endpoint: 3, name: "Sampler · USB MIDI")
    ])
    model.startMaster()
    model.setFollowing(model.devices[2], false)
    model.devices[2].setBPM(90)
    if ProcessInfo.processInfo.environment["MIDI_CLOCK_PREVIEW"] == "disconnected" {
        model.reconcile(model.devices.prefix(2).map(\.output))
    }
    if ["link", "link-ratio"].contains(ProcessInfo.processInfo.environment["MIDI_CLOCK_PREVIEW"] ?? "") {
        model.stopMaster()
        model.setLinkEnabled(true)
    }
    return model
}

private final class PreviewLink: LinkControlling {
    var bpm: Double
    var playing = false
    var stamp = 0.0
    var transportRevision: UInt64 = 0
    init(bpm: Double) { self.bpm = bpm }
    func setEnabled(_ enabled: Bool) -> Bool { true }
    func setTransportSync(_ enabled: Bool) {}
    func setTempo(_ bpm: Double, at time: Double) { self.bpm = bpm }
    func setPlaying(_ playing: Bool, at time: Double) { self.playing = playing; stamp = time; transportRevision += 1 }
    func timeline(at time: Double) -> BeatTimeline { state(at: time).timeline }
    func state(at time: Double) -> LinkState {
        let scale = LinkSession.tempoScale(for: bpm)
        return LinkState(timeline: BeatTimeline(hostTime: time, beat: time * bpm * scale / 60, secondsPerBeat: 60 / (bpm * scale), bpm: bpm * scale),
                         sessionBPM: bpm, tempoScale: scale, peers: 2, playing: playing, transportTime: stamp, transportRevision: transportRevision)
    }
}
#endif
