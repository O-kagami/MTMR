import Foundation

/// Rejects stale reads issued before the latest user interaction or mode change.
struct LevelReadGate {
    private(set) var generation: UInt64 = 0
    private var lastInteraction: TimeInterval = -.infinity
    let settleDelay: TimeInterval

    init(settleDelay: TimeInterval = 0.6) { self.settleDelay = settleDelay }
    mutating func interacted(at time: TimeInterval) {
        generation &+= 1
        lastInteraction = time
    }
    mutating func invalidate() { generation &+= 1 }
    func allows(_ issuedGeneration: UInt64, issuedAt: TimeInterval, completedAt: TimeInterval) -> Bool {
        issuedAt.isFinite && completedAt.isFinite && completedAt >= issuedAt &&
            issuedGeneration == generation && issuedAt - lastInteraction >= settleDelay
    }
}

/// Gives the UI an honest value when a device rejects or cannot perform a write.
enum LevelWritePolicy {
    enum Result: Equatable { case accepted(Float), reverted(Float), unavailable }
    static func apply(_ requested: Float, write: (Float) -> Bool, readActual: () -> Float?) -> Result {
        if requested.isFinite, (0...100).contains(requested), write(requested) {
            return .accepted(requested)
        }
        guard let actual = readActual(), actual.isFinite, (0...100).contains(actual) else { return .unavailable }
        return .reverted(actual)
    }
}
