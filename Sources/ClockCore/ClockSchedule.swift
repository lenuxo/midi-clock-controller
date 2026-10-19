import Foundation

/// Absolute deadlines avoid accumulating timer wake-up error. Units are seconds.
public struct ClockSchedule {
    public static let bpmRange = 20.0...300.0
    public private(set) var bpm: Double
    public private(set) var next: Double
    public private(set) var last: Double?
    private var anchor: Double
    private var index = 0
    public var interval: Double { 60 / (bpm * 24) }

    public init(bpm: Double, start: Double) {
        self.bpm = Self.clamp(bpm)
        next = start
        anchor = start
    }

    public static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(bpmRange.upperBound, max(bpmRange.lowerBound, value)) : 120
    }

    /// Already submitted events stay intact; the new tempo begins at the next deadline.
    public mutating func setBPM(_ value: Double) {
        let clamped = Self.clamp(value)
        guard clamped != bpm else { return }
        bpm = clamped
        anchor = next
        index = 0
    }

    /// Rebase after a small scheduling delay without squeezing the following interval.
    internal mutating func delayNext(until time: Double) {
        guard next < time else { return }
        anchor = time
        index = 0
        next = time
    }

    public mutating func pop(through horizon: Double) -> Double? {
        guard next <= horizon else { return nil }
        let result = next
        last = result
        index += 1
        next = anchor + Double(index) * interval
        return result
    }
}
