import XCTest
import ClockCore
@testable import LinkBridge
@testable import MIDIClockController

@MainActor
final class LinkControllerTests: XCTestCase {
    private func setup() -> (AppModel, FakeLink, () -> [LinkTransport]) {
        let link = FakeLink()
        var transports: [LinkTransport] = []
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, discover: false,
                             linkFactory: { _ in link }, factory: {
            let transport = LinkTransport(); transports.append(transport); return transport
        })
        model.reconcile((1...3).map { MIDIOutput(id: Int32($0), endpoint: UInt32($0), name: "Test \($0)") })
        model.setFollowing(model.devices[2], false)
        return (model, link, { transports })
    }

    func testJoiningAdoptsSessionTempoWithoutPublishingOrStarting() {
        let (model, link, _) = setup()
        defer { model.shutdown() }
        link.bpm = 137.37
        model.setLinkEnabled(true)
        XCTAssertEqual(model.masterBPM, 137.37)
        XCTAssertEqual(model.devices[0].bpm, 137.4)
        XCTAssertEqual(model.devices[2].bpm, 120)
        XCTAssertEqual(model.playingCount, 0)
        XCTAssertTrue(link.tempoEdits.isEmpty)
        XCTAssertTrue(link.transportEdits.isEmpty)
        model.startMaster()
        XCTAssertTrue(link.tempoEdits.isEmpty, "Starting must not publish a rounded display value")
    }

    func testRemoteTempoTransportAndEmergencyStopAreIsolated() {
        let (model, link, transports) = setup()
        defer { model.shutdown() }
        model.devices[2].start()
        model.setLinkEnabled(true)
        model.setLinkStartStopSync(true)
        link.bpm = 150
        link.remotePlay(true)
        model.pollLink()
        XCTAssertEqual(model.playingCount, 3)
        XCTAssertEqual(model.devices[2].bpm, 120)
        XCTAssertTrue(link.transportEdits.isEmpty, "Remote event must not echo back")
        XCTAssertEqual(transports().filter { $0.beatClock != nil }.count, 2)
        link.remotePlay(false)
        model.pollLink()
        XCTAssertEqual(model.playingCount, 1)
        XCTAssertTrue(model.devices[0].canContinue)
        link.remotePlay(true)
        model.pollLink()
        XCTAssertEqual(model.playingCount, 3)
        XCTAssertEqual(transports().reduce(0) { $0 + $1.resumes }, 2)
        model.stopAll()
        XCTAssertFalse(model.linkStartStopSync)
        link.remotePlay(false); model.pollLink()
        link.remotePlay(true); model.pollLink()
        XCTAssertEqual(model.playingCount, 0)
    }

    func testLocalTransportPublishesOnceAndSyncEnableIgnoresOldState() {
        let (model, link, _) = setup()
        defer { model.shutdown() }
        link.remotePlay(true)
        model.setLinkEnabled(true)
        model.setLinkStartStopSync(true)
        model.pollLink()
        XCTAssertEqual(model.playingCount, 0)
        model.startMaster()
        model.pollLink()
        XCTAssertEqual(link.transportEdits, [true])
        model.stopMaster()
        model.pollLink()
        XCTAssertEqual(link.transportEdits, [true, false])
        XCTAssertEqual(model.playingCount, 0)
    }

    func testDetachingRunningDeviceLeavesItUnaffectedByLaterLinkChanges() {
        let (model, link, transports) = setup()
        defer { model.shutdown() }
        model.setLinkEnabled(true)
        model.startMaster()
        model.setFollowing(model.devices[0], false)
        XCTAssertNil(transports()[0].beatClock)
        XCTAssertTrue(model.devices[0].running)
        link.bpm = 160
        model.pollLink()
        XCTAssertEqual(model.devices[0].bpm, 120)
        XCTAssertEqual(model.devices[1].bpm, 160)
        model.setMasterBPM(170)
        XCTAssertEqual(link.tempoEdits, [170])
    }

    func testOutOfRangeDisplayAndExplicitEditStayConsistent() {
        let (model, link, _) = setup()
        defer { model.shutdown() }
        link.bpm = 999
        model.setLinkEnabled(true)
        XCTAssertEqual(model.masterBPM, 249.75)
        XCTAssertEqual(model.linkTempoScale, 0.25)
        model.setMasterBPM(250)
        XCTAssertEqual(link.bpm, 1000)
        XCTAssertEqual(model.masterBPM, 250)
        model.setMasterBPM(20)
        XCTAssertEqual(link.bpm, 20)
        XCTAssertEqual(model.masterBPM, 20)
    }

    func testFailedLocalFollowersDoNotLeaveSourceSwitchLocked() {
        let (model, _, transports) = setup()
        defer { model.shutdown() }
        model.startMaster()
        for transport in transports() { transport.onFailure?("Injected") }
        XCTAssertEqual(model.playbackAction, .start)
        model.setLinkEnabled(true)
        XCTAssertTrue(model.linkEnabled)
        XCTAssertFalse(model.masterRunning)
    }

    func testSourceSwitchRequiresStoppedFollowersAndShutdownDisablesNetwork() {
        let (model, link, _) = setup()
        model.startMaster()
        model.setLinkEnabled(true)
        XCTAssertFalse(model.linkEnabled)
        model.stopMaster()
        model.setLinkEnabled(true)
        XCTAssertTrue(model.linkEnabled)
        model.shutdown()
        XCTAssertFalse(link.enabled)
    }
}

private final class LinkTransport: DeviceTransport {
    var onFailure: ((String) -> Void)?
    var beatClock: BeatClock?
    var resumes = 0
    func setBeatClock(_ clock: BeatClock?, quantum: Double) { beatClock = clock }
    func start(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws {}
    func resume(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws { resumes += 1 }
    func setBPM(_ bpm: Double) {}
    func scheduleBPM(_ bpm: Double, at deadline: Double) {}
    func drainPendingStop() {}
    func scheduleStop(at deadline: Double) throws {}
    func stop() throws {}
    func shutdown() {}
}

private final class FakeLink: LinkControlling {
    var bpm = 120.0, playing = false, stamp = 0.0, enabled = false
    var tempoEdits: [Double] = [], transportEdits: [Bool] = []
    func setEnabled(_ enabled: Bool) -> Bool { self.enabled = enabled; return true }
    func setTransportSync(_ enabled: Bool) {}
    func setTempo(_ bpm: Double, at time: Double) { tempoEdits.append(bpm); self.bpm = bpm }
    func setPlaying(_ playing: Bool, at time: Double) { transportEdits.append(playing); remotePlay(playing) }
    func remotePlay(_ value: Bool) { playing = value; stamp += 1 }
    func timeline(at hostTime: Double) -> BeatTimeline { state(at: hostTime).timeline }
    func state(at time: Double) -> LinkState {
        let scale = LinkSession.tempoScale(for: bpm)
        return LinkState(timeline: BeatTimeline(hostTime: time, beat: 0, secondsPerBeat: 60 / (bpm * scale), bpm: bpm * scale),
                  sessionBPM: bpm, tempoScale: scale, peers: 1, playing: playing, transportTime: stamp)
    }
}

extension LinkControllerTests {
    func testDisconnectedDeviceRouteTracksLinkSwitchesBeforeReconnection() {
        let (model, link, transports) = setup()
        defer { model.shutdown() }
        let outputs = model.devices.map(\.output)
        model.setLinkEnabled(true)
        model.startMaster()
        model.stopMaster()
        let transport = transports()[0]
        XCTAssertTrue(transport.beatClock === link)
        model.reconcile(Array(outputs.dropFirst()))
        XCTAssertFalse(model.devices[0].online)
        model.setLinkEnabled(false)
        XCTAssertNil(transport.beatClock, "Offline followers must release the old Link route too")
        model.setLinkEnabled(true)
        XCTAssertTrue(transport.beatClock === link)
        model.reconcile(outputs)
        XCTAssertTrue(model.devices[0].online)
        XCTAssertFalse(model.devices[0].running)
        XCTAssertTrue(transport.beatClock === link)
    }
}
