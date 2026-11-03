import XCTest
@testable import LinkBridge

final class LinkSessionTests: XCTestCase {
    func testOfficialSDKTimelineMapsHostTimeWithoutNetwork() throws {
        let session = try XCTUnwrap(LinkSession(bpm: 120))
        let time = LinkSession.hostTime()
        let state = session.state(at: time)
        XCTAssertEqual(state.peers, 0)
        XCTAssertEqual(state.timeline.bpm, 120)
        XCTAssertTrue(state.timeline.valid)
        XCTAssertEqual(state.timeline.time(at: state.timeline.beat + 1) - time, 0.5, accuracy: 0.00001)
        session.setTempo(150, at: time)
        XCTAssertEqual(session.state(at: time).timeline.bpm, 150)
        session.setPlaying(true, at: time)
        XCTAssertTrue(session.state(at: time).playing)
    }
    func testOutOfRangeTempoUsesOctaveRatio() {
        XCTAssertEqual(LinkSession.tempoScale(for: 999), 0.25)
        XCTAssertEqual(LinkSession.tempoScale(for: 10), 2)
        XCTAssertEqual(LinkSession.tempoScale(for: 120), 1)
    }
}

extension LinkSessionTests {
    func testTwoOfficialPeersDiscoverAndShareTempoPhaseAndTransport() throws {
        guard ProcessInfo.processInfo.environment["REQUIRE_LINK_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("Set REQUIRE_LINK_NETWORK_TESTS=1 to run real local-network discovery")
        }
        let a = try XCTUnwrap(LinkSession(bpm: 120))
        let b = try XCTUnwrap(LinkSession(bpm: 120))
        XCTAssertTrue(a.setEnabled(true)); XCTAssertTrue(b.setEnabled(true))
        defer { _ = a.setEnabled(false); _ = b.setEnabled(false) }
        func waitUntil(_ predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if predicate() { return true }
                Thread.sleep(forTimeInterval: 0.02)
            }
            return false
        }
        guard waitUntil({ a.state(at: LinkSession.hostTime()).peers > 0 && b.state(at: LinkSession.hostTime()).peers > 0 }) else {
            XCTFail("Official Link peers could not discover each other"); return
        }
        guard a.state(at: LinkSession.hostTime()).peers == 1 && b.state(at: LinkSession.hostTime()).peers == 1 else {
            throw XCTSkip("Unexpected external Link peers; no tempo or transport commands sent")
        }
        a.setTempo(137.3, at: LinkSession.hostTime() + 0.05)
        XCTAssertTrue(waitUntil { abs(b.state(at: LinkSession.hostTime()).sessionBPM - 137.3) < 0.001 })
        b.setTempo(150, at: LinkSession.hostTime() + 0.05)
        XCTAssertTrue(waitUntil { abs(a.state(at: LinkSession.hostTime()).sessionBPM - 150) < 0.001 })
        XCTAssertTrue(waitUntil {
            let time = LinkSession.hostTime()
            let difference = a.timeline(at: time).beat - b.timeline(at: time).beat
            return abs(difference - (difference / 4).rounded() * 4) < 0.005
        })
        a.setTransportSync(true); b.setTransportSync(true)
        a.setPlaying(true, at: LinkSession.hostTime())
        XCTAssertTrue(waitUntil { b.state(at: LinkSession.hostTime()).playing })
        b.setPlaying(false, at: LinkSession.hostTime())
        XCTAssertTrue(waitUntil { !a.state(at: LinkSession.hostTime()).playing })
    }
}

extension LinkSessionTests {
    func testTransportRevisionComesFromOfficialCallbackNotTempoMapping() async throws {
        let session = try XCTUnwrap(LinkSession(bpm: 120)) // Network stays disabled.
        func waitForRevision(after revision: UInt64) async -> Bool {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if session.state(at: LinkSession.hostTime()).transportRevision > revision { return true }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            return false
        }
        let initial = session.state(at: LinkSession.hostTime()).transportRevision
        session.setPlaying(true, at: LinkSession.hostTime())
        let started = await waitForRevision(after: initial)
        XCTAssertTrue(started)
        let playing = session.state(at: LinkSession.hostTime())
        XCTAssertTrue(playing.playing)
        session.setTempo(170, at: LinkSession.hostTime())
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(session.state(at: LinkSession.hostTime()).transportRevision, playing.transportRevision)
        session.setPlaying(false, at: LinkSession.hostTime())
        let stopped = await waitForRevision(after: playing.transportRevision)
        XCTAssertTrue(stopped)
        XCTAssertFalse(session.state(at: LinkSession.hostTime()).playing)
    }
}
