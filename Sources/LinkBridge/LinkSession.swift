import Foundation
import CoreAudio
import CLink
import ClockCore

public struct LinkState {
    public let timeline: BeatTimeline
    public let sessionBPM: Double
    public let tempoScale: Double
    public let peers: Int
    public let playing: Bool
    public let transportTime: Double
    public let transportRevision: UInt64
    public let callbackPlaying: Bool
    public init(timeline: BeatTimeline, sessionBPM: Double, tempoScale: Double, peers: Int, playing: Bool, transportTime: Double, transportRevision: UInt64 = 0, callbackPlaying: Bool? = nil) {
        self.timeline = timeline; self.sessionBPM = sessionBPM; self.tempoScale = tempoScale
        self.peers = peers; self.playing = playing; self.transportTime = transportTime
        self.transportRevision = transportRevision
        self.callbackPlaying = callbackPlaying ?? playing
    }
}

public protocol LinkControlling: BeatClock {
    func setEnabled(_ enabled: Bool) -> Bool
    func setTransportSync(_ enabled: Bool)
    func state(at time: Double) -> LinkState
    func setTempo(_ bpm: Double, at time: Double)
    func setPlaying(_ playing: Bool, at time: Double)
}

/// No network activity until explicitly enabled. The native SDK owns discovery/drift correction.
public final class LinkSession: LinkControlling {
    private let handle: MCLLink
    public init?(bpm: Double) {
        guard let handle = mcl_create(bpm) else { return nil }
        self.handle = handle
    }
    deinit { _ = mcl_enable(handle, false); mcl_destroy(handle) }
    public static func hostTime() -> Double { Double(AudioGetCurrentHostTime()) / AudioGetHostClockFrequency() }
    public func setEnabled(_ enabled: Bool) -> Bool { mcl_enable(handle, enabled) }
    public func setTransportSync(_ enabled: Bool) { mcl_sync_transport(handle, enabled) }
    public func setTempo(_ bpm: Double, at time: Double) { mcl_set_tempo(handle, bpm, time) }
    public func setPlaying(_ playing: Bool, at time: Double) { mcl_set_playing(handle, playing, time) }
    public func timeline(at hostTime: Double) -> BeatTimeline { state(at: hostTime).timeline }
    public func state(at time: Double) -> LinkState {
        let native = mcl_snapshot(handle, time)
        let scale = Self.tempoScale(for: native.tempo)
        let timeline = BeatTimeline(hostTime: time, beat: native.beat * scale,
                                    secondsPerBeat: native.seconds_per_beat / scale, bpm: native.tempo * scale, beatScale: scale)
        return LinkState(timeline: timeline, sessionBPM: native.tempo, tempoScale: scale,
                         peers: Int(native.peers), playing: native.playing, transportTime: native.transport_time,
                         transportRevision: native.transport_revision, callbackPlaying: native.callback_playing)
    }
    /// Octave-fold unusual session tempos instead of silently clipping and losing phase.
    public static func tempoScale(for bpm: Double) -> Double {
        guard bpm.isFinite, bpm >= 1e-12, bpm <= 1e12 else { return 1 }
        var scale = 1.0
        while bpm * scale < 20 { scale *= 2 }
        while bpm * scale > 300 { scale /= 2 }
        return scale
    }
}
