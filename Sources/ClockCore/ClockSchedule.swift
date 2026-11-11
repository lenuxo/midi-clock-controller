import Foundation

/// Absolute deadlines avoid accumulating timer wake-up error. Units are seconds.
public struct ClockSchedule {
    public static let bpmRange = 20.0...300.0
    public private(set) var bpm: Double
    public var next: Double { gridTime + phaseDelay }
    private(set) var gridTime: Double
    private var phaseDelay = 0.0
    private let preserveGrid: Bool
    public private(set) var last: Double?
    private var anchor: Double
    private var index = 0
    public var interval: Double { 60 / (bpm * 24) }

    public init(bpm: Double, start: Double, preserveGrid: Bool = false) {
        self.preserveGrid = preserveGrid
        self.bpm = Self.clamp(bpm)
        gridTime = start
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
        anchor = gridTime
        index = 0
    }

    /// Rebase after a small scheduling delay without squeezing the following interval.
    internal mutating func delayNext(until time: Double) {
        guard next < time else { return }
        if preserveGrid {
            // A group shares its original host-time grid. Keep every tick and
            // recover phase gradually (at most 2% of one interval per pulse).
            phaseDelay = time - gridTime
            return
        }
        anchor = time
        index = 0
        gridTime = time
    }

    public mutating func pop(through horizon: Double) -> Double? {
        guard next <= horizon else { return nil }
        let result = next
        last = result
        index += 1
        phaseDelay = max(0, phaseDelay - interval * 0.02)
        gridTime = anchor + Double(index) * interval
        return result
    }
}
