import Foundation

struct TouchBarBrightnessSnapshot: Equatable {
    let automatic: Bool
    let brightness: Double
}

protocol TouchBarBrightnessDevice {
    func read() -> TouchBarBrightnessSnapshot?
}

/// Read-only until the private API's persistence and conflict behavior can be
/// verified. No user action, timeout, or termination can write device state.
final class TouchBarBrightnessSession {
    private let device: TouchBarBrightnessDevice
    init(device: TouchBarBrightnessDevice) { self.device = device }
    func read() -> TouchBarBrightnessSnapshot? { device.read() }
}

/// Exact payload contract for one transient request. `Commit` is undocumented,
/// so macOS retaining or applying the value is not guaranteed.
enum TemporaryBrightnessPolicy {
    static func payload(_ value: Double) -> [String: Any]? {
        guard value.isFinite, (0.05...1).contains(value) else { return nil }
        return ["Brightness": value, "Commit": false, "CommitType": 0]
    }
}
