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
    var revision: UInt64 = 0
    var onSetPlaying: (() -> Void)?
    func setEnabled(_ enabled: Bool) -> Bool { self.enabled = enabled; return true }
    func setTransportSync(_ enabled: Bool) {}
    func setTempo(_ bpm: Double, at time: Double) { tempoEdits.append(bpm); self.bpm = bpm }
    func setPlaying(_ playing: Bool, at time: Double) { transportEdits.append(playing); remotePlay(playing); onSetPlaying?() }
    func remotePlay(_ value: Bool) { playing = value; stamp += 1; revision += 1 }
    func timeline(at hostTime: Double) -> BeatTimeline { state(at: hostTime).timeline }
    func state(at time: Double) -> LinkState {
        let scale = LinkSession.tempoScale(for: bpm)
        return LinkState(timeline: BeatTimeline(hostTime: time, beat: 0, secondsPerBeat: 60 / (bpm * scale), bpm: bpm * scale),
                  sessionBPM: bpm, tempoScale: scale, peers: 1, playing: playing, transportTime: stamp, transportRevision: revision)
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

extension LinkControllerTests {
    func testOfficialPeersDriveControllerTransportWithoutMIDIDevices() async throws {
        guard ProcessInfo.processInfo.environment["REQUIRE_LINK_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("Set REQUIRE_LINK_NETWORK_TESTS=1 on an isolated network")
        }
        let local = try XCTUnwrap(LinkSession(bpm: 120))
        let remote = try XCTUnwrap(LinkSession(bpm: 120))
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, discover: false,
                             linkFactory: { _ in local }, factory: { LinkTransport() })
        defer { model.shutdown(); _ = remote.setEnabled(false) }
        model.setLinkEnabled(true)
        XCTAssertTrue(remote.setEnabled(true))
        func waitUntil(_ predicate: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if predicate() { return true }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            return false
        }
        let discovered = await waitUntil { local.state(at: LinkSession.hostTime()).peers > 0 && remote.state(at: LinkSession.hostTime()).peers > 0 }
        guard discovered else { XCTFail("Link peers did not discover each other"); return }
        guard local.state(at: LinkSession.hostTime()).peers == 1 && remote.state(at: LinkSession.hostTime()).peers == 1 else {
            throw XCTSkip("Unexpected external Link peers; no tempo or transport commands sent")
        }
        model.setLinkStartStopSync(true)
        remote.setTransportSync(true)
        for _ in 0..<5 {
            remote.setPlaying(true, at: LinkSession.hostTime())
            let started = await waitUntil { model.playbackAction == .stop }
            XCTAssertTrue(started, "The real SDK must update controller UI even without MIDI devices")
            remote.setPlaying(false, at: LinkSession.hostTime())
            let stopped = await waitUntil { model.playbackAction != .stop }
            XCTAssertTrue(stopped)
        }
    }
}

extension LinkControllerTests {
    func testRemoteReversalDuringLocalPublishIsNotSwallowed() {
        let (model, link, _) = setup()
        defer { model.shutdown() }
        model.setLinkEnabled(true)
        model.setLinkStartStopSync(true)
        model.startMaster()
        model.pollLink()
        link.onSetPlaying = { link.remotePlay(true) }
        model.stopMaster()
        XCTAssertEqual(model.playingCount, 0)
        model.pollLink()
        XCTAssertEqual(model.playingCount, 2, "A newer remote Play must not be recorded as our Stop acknowledgement")
        XCTAssertEqual(model.playbackAction, .stop)
        link.onSetPlaying = nil
    }

    func testTimelineCorrectionDoesNotRestartReconnectedFollower() {
        let (model, link, _) = setup()
        defer { model.shutdown() }
        model.setLinkEnabled(true)
        model.setLinkStartStopSync(true)
        link.remotePlay(true)
        model.pollLink()
        let outputs = model.devices.map(\.output)
        model.reconcile(Array(outputs.dropFirst()))
        model.reconcile(outputs)
        XCTAssertFalse(model.devices[0].running)
        link.stamp += 0.001 // SDK beat/time remapping, not a transport notification.
        model.pollLink()
        XCTAssertFalse(model.devices[0].running)
        XCTAssertTrue(model.devices[1].running)
    }

    func testTimelineRemappingDoesNotConsumeOldSessionPlayback() {
        let (model, link, _) = setup()
        defer { model.shutdown() }
        model.setLinkEnabled(true)
        model.setLinkStartStopSync(true)
        link.playing = true
        link.stamp += 0.001 // Session timing correction may map cached session state.
        model.pollLink()
        XCTAssertEqual(model.playingCount, 0)
        link.remotePlay(false)
        model.pollLink()
        link.remotePlay(true)
        model.pollLink()
        XCTAssertEqual(model.playingCount, 2)
    }

    func testRemoteTransportUpdatesUIWithoutFollowersAndRapidAlternation() {
        let (model, link, _) = setup()
        defer { model.shutdown() }
        model.reconcile([])
        model.setLinkEnabled(true)
        model.setLinkStartStopSync(true)
        for _ in 0..<20 {
            link.remotePlay(true); model.pollLink()
            XCTAssertTrue(model.masterRunning)
            XCTAssertEqual(model.playbackAction, .stop)
            link.remotePlay(false); model.pollLink()
            XCTAssertFalse(model.masterRunning)
            XCTAssertEqual(model.playbackAction, .start)
        }
    }
}

extension LinkControllerTests {
    func testDelayedLocalCallbackDoesNotRetryFailedFollower() {
        let (model, link, transports) = setup()
        defer { model.shutdown() }
        model.setLinkEnabled(true)
        model.setLinkStartStopSync(true)
        model.startMaster()
        link.revision -= 1 // Local state is committed before the SDK callback arrives.
        transports()[0].onFailure?("Injected output failure")
        model.pollLink()
        XCTAssertFalse(model.devices[0].running)
        link.revision += 1
        model.pollLink()
        XCTAssertFalse(model.devices[0].running, "Our asynchronous acknowledgement must not echo as a new remote Play")
        XCTAssertTrue(model.devices[1].running)
    }
}
