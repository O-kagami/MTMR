import Foundation

/// Rejects slider actions while the machine or display is asleep and while
/// AppKit and the display service are settling after a wake notification.
struct BrightnessWakeGuard {
    private var systemAsleep = false
    private var displayAsleep = false
    private var readyAt: TimeInterval = -.infinity
    mutating func systemWillSleep() { systemAsleep = true }
    mutating func displayDidSleep() { displayAsleep = true }
    mutating func systemDidWake(at time: TimeInterval) { systemAsleep = false; readyAt = time + 2 }
    mutating func displayDidWake(at time: TimeInterval) { displayAsleep = false; readyAt = time + 2 }
    func allowsWrite(at time: TimeInterval) -> Bool {
        time.isFinite && !systemAsleep && !displayAsleep && time >= readyAt
    }
}

/// Validates a requested level before invoking the platform's display writer.
struct BrightnessWriter {
    enum Result: Equatable { case accepted, invalid, unavailable, failed(Int32) }
    static func apply(_ value: Float, write: ((Float) -> Int32)?) -> Result {
        guard value.isFinite, (0...1).contains(value) else { return .invalid }
        guard let write = write else { return .unavailable }
        let status = write(value)
        return status == 0 ? .accepted : .failed(status)
    }
}
