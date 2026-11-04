import Foundation

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
