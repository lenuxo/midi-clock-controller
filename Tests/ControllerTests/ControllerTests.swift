import XCTest
@testable import MIDIClockController
@testable import ClockCore

final class ControllerTests: XCTestCase {
    @MainActor
    func testMasterFirstAndIndependentOverride() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var transports: [FakeTransport] = []
        let model = AppModel(defaults: defaults, discover: false, factory: {
            let engine = FakeTransport(); transports.append(engine); return engine
        })
        model.reconcile([MIDIOutput(id: 1, endpoint: 1, name: "Drums"), MIDIOutput(id: 2, endpoint: 2, name: "Synth")])
        XCTAssertEqual(model.followers.count, 2)
        model.startMaster()
        XCTAssertEqual(model.playingCount, 2)
        XCTAssertEqual(transports[0].starts.first, transports[1].starts.first)
        let independent = model.devices[1]
        model.setFollowing(independent, false)
        XCTAssertTrue(independent.running, "Detaching must not interrupt playback")
        independent.setBPM(90)
        model.setMasterBPM(140)
        XCTAssertEqual(model.devices[0].bpm, 140)
        XCTAssertEqual(independent.bpm, 90)
        model.stopMaster()
        XCTAssertFalse(model.devices[0].running)
        XCTAssertTrue(independent.running)
        model.setFollowing(independent, true)
        XCTAssertEqual(independent.bpm, 140)
        XCTAssertFalse(independent.running)
        model.startMaster()
        model.stopAll()
        XCTAssertEqual(model.playingCount, 0)
        XCTAssertFalse(model.masterRunning)
    }

    @MainActor
    func testDisconnectAndFailureAreLocalAndReconnectDoesNotStart() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var transports: [FakeTransport] = []
        let model = AppModel(defaults: defaults, discover: false, factory: {
            let engine = FakeTransport(); transports.append(engine); return engine
        })
        let a = MIDIOutput(id: 1, endpoint: 1, name: "A")
        let b = MIDIOutput(id: 2, endpoint: 2, name: "B")
        model.reconcile([a, b]); model.startMaster()
        model.reconcile([b])
        XCTAssertFalse(model.devices[0].online)
        XCTAssertTrue(model.devices[1].running)
        model.reconcile([a, b])
        XCTAssertTrue(model.devices[0].online)
        XCTAssertFalse(model.devices[0].running)
        model.startMaster()
        transports[0].onFailure?("Injected failure")
        XCTAssertFalse(model.devices[0].running)
        XCTAssertTrue(model.devices[1].running)
        XCTAssertNotNil(model.devices[0].error)
        model.shutdown()
    }

    @MainActor
    func testInvalidMasterTempoDoesNotChangeOrStartDevices() {
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, discover: false, factory: { FakeTransport() })
        model.reconcile([MIDIOutput(id: 1, endpoint: 1, name: "A")])
        model.masterBPMText = "999"
        model.startMaster()
        XCTAssertEqual(model.playingCount, 0)
        XCTAssertEqual(model.devices[0].bpm, 120)
        XCTAssertNotNil(model.error)
    }
}

private final class FakeTransport: DeviceTransport {
    var onFailure: ((String) -> Void)?
    var starts: [Double?] = []
    var stops: [Double] = []
    func start(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws { starts.append(scheduledAt) }
    func setBPM(_ bpm: Double) {}
    func scheduleBPM(_ bpm: Double, at deadline: Double) {}
    func drainPendingStop() {}
    func scheduleStop(at deadline: Double) throws { stops.append(deadline) }
    func stop() throws {}
    func shutdown() {}
}
