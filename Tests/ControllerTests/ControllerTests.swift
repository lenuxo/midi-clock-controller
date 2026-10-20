import XCTest
@testable import MIDIClockController
@testable import ClockCore

final class ControllerTests: XCTestCase {
    @MainActor
    func testPrimaryActionFollowsPlaybackAndReconnectState() {
        let transport = FakeTransport()
        let output = MIDIOutput(id: 1, endpoint: 1, name: "Test")
        let device = DeviceControl(output: output, defaults: UserDefaults(suiteName: UUID().uuidString)!, factory: { transport })
        XCTAssertEqual(device.playbackAction, .start)
        device.performPlaybackAction()
        XCTAssertEqual(device.playbackAction, .stop)
        device.performPlaybackAction()
        XCTAssertEqual(device.playbackAction, .resume)
        device.performPlaybackAction()
        XCTAssertEqual(transport.starts.count, 1)
        XCTAssertEqual(transport.resumes.count, 1)
        device.performPlaybackAction()
        device.start() // Explicit secondary action resets to the beginning.
        XCTAssertEqual(transport.starts.count, 2)
        device.update(output: nil)
        device.performPlaybackAction()
        XCTAssertFalse(device.running)
        device.update(output: output)
        XCTAssertEqual(device.playbackAction, .start)
        device.performPlaybackAction()
        XCTAssertEqual(transport.starts.count, 3)
        transport.onFailure?("Injected failure")
        XCTAssertEqual(device.playbackAction, .start)
    }

    @MainActor
    func testMixedFollowersContinueOnlyEligibleDevicesAndPrimaryRemainsStop() {
        var transports: [FakeTransport] = []
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, discover: false, factory: {
            let transport = FakeTransport(); transports.append(transport); return transport
        })
        let a = MIDIOutput(id: 1, endpoint: 1, name: "A")
        let b = MIDIOutput(id: 2, endpoint: 2, name: "B")
        let c = MIDIOutput(id: 3, endpoint: 3, name: "Independent")
        model.reconcile([a, b, c])
        model.setFollowing(model.devices[2], false)
        model.devices[2].start()
        XCTAssertEqual(model.playbackAction, .start)
        model.performPlaybackAction()
        XCTAssertEqual(model.playbackAction, .stop)
        model.performPlaybackAction()
        model.reconcile([a, c])
        model.reconcile([a, b, c])
        XCTAssertEqual(model.playbackAction, .resume)
        XCTAssertEqual(model.resumableFollowers.count, 1)
        model.performPlaybackAction()
        XCTAssertTrue(model.devices[0].running)
        XCTAssertFalse(model.devices[1].running)
        XCTAssertEqual(model.playbackAction, .stop, "Waiting devices must not turn Stop into Start")
        XCTAssertEqual(transports[1].resumes.count, 1)
        XCTAssertTrue(transports[2].resumes.isEmpty)
        model.performPlaybackAction()
        model.startMaster() // All followers from beginning, independent untouched.
        XCTAssertEqual(model.playingCount, 3)
        XCTAssertEqual(transports[0].starts.count, 1)
        XCTAssertEqual(transports[1].starts.count, 2)
        XCTAssertEqual(transports[2].starts.count, 2)
        model.shutdown()
    }

    @MainActor
    func testContinueUsesSharedDeadlineAndLeavesIndependentDeviceAlone() {
        var transports: [FakeTransport] = []
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, discover: false, factory: {
            let transport = FakeTransport(); transports.append(transport); return transport
        })
        model.reconcile((1...3).map { MIDIOutput(id: Int32($0), endpoint: UInt32($0), name: "Test \($0)") })
        model.continueMaster()
        XCTAssertEqual(model.playingCount, 0, "Fresh connections have no known stopped position")
        model.startMaster()
        let independent = model.devices[2]
        model.setFollowing(independent, false)
        model.stopMaster()
        XCTAssertTrue(independent.running)
        XCTAssertTrue(model.devices[0].canContinue)
        model.setMasterBPM(180)
        model.continueMaster()
        XCTAssertEqual(model.playingCount, 3)
        XCTAssertEqual(transports[0].resumes.count, 1)
        XCTAssertEqual(transports[0].resumes.first, transports[1].resumes.first)
        XCTAssertTrue(transports[2].resumes.isEmpty)
        XCTAssertEqual(model.devices[0].bpm, 180)
        independent.stop()
        independent.resume()
        XCTAssertEqual(transports[2].resumes.count, 1)
        independent.resume()
        XCTAssertEqual(transports[2].resumes.count, 1, "Running Continue is a no-op")
        model.stopAll()
        model.startMaster()
        XCTAssertEqual(transports[0].starts.count, 2, "From beginning must still send Start")
        model.shutdown()
    }

    @MainActor
    func testDisconnectAndTransportErrorsInvalidateContinue() {
        let transport = FakeTransport()
        let device = DeviceControl(output: MIDIOutput(id: 1, endpoint: 1, name: "Test"),
                                   defaults: UserDefaults(suiteName: UUID().uuidString)!, factory: { transport })
        device.start(); device.stop()
        XCTAssertTrue(device.canContinue)
        device.update(output: nil)
        device.update(output: MIDIOutput(id: 1, endpoint: 2, name: "Test"))
        device.resume()
        XCTAssertFalse(device.canContinue)
        XCTAssertFalse(device.running)
        XCTAssertTrue(transport.resumes.isEmpty)
        device.start()
        transport.onFailure?("Injected failure")
        XCTAssertFalse(device.canContinue)
        device.start()
        transport.failStop = true
        device.stop()
        XCTAssertFalse(device.canContinue)
        XCTAssertNotNil(device.error)
    }

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
    var resumes: [Double?] = []
    var failStop = false
    var stops: [Double] = []
    func start(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws { starts.append(scheduledAt) }
    func resume(outputs: [MIDIOutput], bpm: Double, scheduledAt: Double?) throws { resumes.append(scheduledAt) }
    func setBPM(_ bpm: Double) {}
    func scheduleBPM(_ bpm: Double, at deadline: Double) {}
    func drainPendingStop() {}
    func scheduleStop(at deadline: Double) throws { stops.append(deadline) }
    func stop() throws { if failStop { throw MIDIError(operation: "Test stop", status: -1) } }
    func shutdown() {}
}

extension ControllerTests {
    @MainActor
    func testDisconnectExpiresOnceWithoutRefreshExtendingDeadline() {
        var callbacks: [@MainActor () -> Void] = []
        var delays: [TimeInterval] = []
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, discover: false,
                             scheduleRemoval: { delay, action in
            delays.append(delay); callbacks.append(action); return {}
        }, factory: { FakeTransport() })
        let a = MIDIOutput(id: 1, endpoint: 1, name: "A")
        let b = MIDIOutput(id: 2, endpoint: 2, name: "B")
        model.reconcile([a, b]); model.startMaster()
        model.reconcile([b]); model.reconcile([b])
        XCTAssertEqual(delays, [30])
        XCTAssertEqual(model.devices.count, 2)
        XCTAssertFalse(model.devices[0].online)
        XCTAssertFalse(model.devices[0].running)
        callbacks[0]()
        XCTAssertEqual(model.devices.map(\.id), [2])
        XCTAssertTrue(model.devices[0].running)
        model.reconcile([a, b])
        XCTAssertFalse(model.devices.first { $0.id == 1 }!.running)
        model.shutdown()
    }

    @MainActor
    func testReconnectAndSecondDisconnectRejectStaleRemoval() {
        var callbacks: [@MainActor () -> Void] = []
        var cancellations = 0
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, discover: false,
                             scheduleRemoval: { _, action in
            callbacks.append(action); return { cancellations += 1 }
        }, factory: { FakeTransport() })
        let output = MIDIOutput(id: 1, endpoint: 1, name: "A")
        model.reconcile([output])
        let original = model.devices[0]
        model.reconcile([])
        model.reconcile([output])
        XCTAssertEqual(cancellations, 1)
        callbacks[0]()
        XCTAssertTrue(model.devices[0] === original)
        XCTAssertTrue(original.online)
        XCTAssertFalse(original.running)
        model.reconcile([])
        callbacks[0]() // Callback from the first disconnect was already queued.
        XCTAssertEqual(model.devices.count, 1)
        callbacks[1]()
        XCTAssertTrue(model.devices.isEmpty)
        model.shutdown()
    }

    @MainActor
    func testShutdownCancelsPendingRemoval() {
        var callback: (@MainActor () -> Void)?
        var cancelled = false
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, discover: false,
                             scheduleRemoval: { _, action in
            callback = action; return { cancelled = true }
        }, factory: { FakeTransport() })
        model.reconcile([MIDIOutput(id: 1, endpoint: 1, name: "A")])
        model.reconcile([])
        model.shutdown()
        XCTAssertTrue(cancelled)
        callback?()
        XCTAssertEqual(model.devices.count, 1)
    }
}
