import Foundation

/// A fresh, immutable mapping in host-clock seconds, safe to pass between queues.
public struct BeatTimeline {
    public let hostTime: Double
    public let beat: Double
    public let secondsPerBeat: Double
    public let bpm: Double
    public let beatScale: Double

    public init(hostTime: Double, beat: Double, secondsPerBeat: Double, bpm: Double, beatScale: Double = 1) {
        self.hostTime = hostTime; self.beat = beat
        self.secondsPerBeat = secondsPerBeat; self.bpm = bpm; self.beatScale = beatScale
    }
    public var valid: Bool {
        hostTime.isFinite && beat.isFinite && secondsPerBeat.isFinite && secondsPerBeat > 0
            && bpm.isFinite && ClockSchedule.bpmRange.contains(bpm)
    }
    public func beat(at time: Double) -> Double { beat + (time - hostTime) / secondsPerBeat }
    public func time(at beat: Double) -> Double { hostTime + (beat - self.beat) * secondsPerBeat }
}

/// Implementations must permit concurrent snapshots; the MIDI queue never calls the UI.
public protocol BeatClock: AnyObject {
    func timeline(at hostTime: Double) -> BeatTimeline
}
