import AppKit

/// Time-based acceleration, independent of the system keyboard repeat preference.
struct TempoRamp {
    static let delay = 0.4
    let start: TimeInterval
    private var last: TimeInterval
    private var remainder = 0.0

    init(start: TimeInterval) { self.start = start; last = start }

    mutating func advance(at now: TimeInterval) -> Double {
        guard now > last else { return 0 }
        let previous = last
        last = now
        let elapsed = now - start - Self.delay
        guard elapsed > 0 else { return 0 }
        // No catch-up burst after the UI was busy. Rate grows quadratically, capped at 40 BPM/s.
        let dt = min(0.15, now - max(previous, start + Self.delay))
        let rate = min(40, 2 + 2 * elapsed * elapsed)
        remainder += dt * rate
        let tenths = floor(remainder * 10 + 1e-8)
        remainder -= tenths / 10
        return tenths / 10
    }
}

/// All callers and timer callbacks run on the main thread, never the MIDI scheduler queue.
final class TempoHold {
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var ramp: TempoRamp?
    private var direction = 1.0
    private var action: ((Double) -> Void)?
    private var allowed: (() -> Bool)?
    var isRunning: Bool { timer != nil }

    init() {
        for name in [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification, NSMenu.didBeginTrackingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.stop() })
        }
    }
    func start(direction: Double, allowed: @escaping () -> Bool, action: @escaping (Double) -> Void) {
        stop()
        guard allowed() else { return }
        self.direction = direction
        self.allowed = allowed
        self.action = action
        ramp = TempoRamp(start: ProcessInfo.processInfo.systemUptime)
        action(direction * 0.1)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }
    private func tick() {
        guard allowed?() == true else { stop(); return }
        let delta = ramp?.advance(at: ProcessInfo.processInfo.systemUptime) ?? 0
        if delta > 0 { action?(direction * delta) }
    }
    func stop() {
        timer?.invalidate()
        timer = nil
        ramp = nil
        action = nil
        allowed = nil
    }
    deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
