#if DEBUG
import Foundation
import ClockCore

// Dedicated UI preview bundle: no CoreMIDI client, ports, or hardware messages.
private final class PreviewTransport: DeviceTransport {
    var onFailure: ((String) -> Void)?
    func start(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws {}
    func resume(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws {}
    func setBPM(_ bpm: Double) {}
    func scheduleBPM(_ bpm: Double, at deadline: Double) {}
    func drainPendingStop() {}
    func scheduleStop(at deadline: Double) throws {}
    func stop() throws {}
    func shutdown() {}
}

@MainActor func previewModel() -> AppModel {
    let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, discover: false,
                         factory: { PreviewTransport() })
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
    return model
}
#endif
