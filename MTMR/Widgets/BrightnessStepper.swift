import Foundation

/// Reconciles a slider target with measured display brightness using one HID key
/// event at a time. Times are monotonic uptime seconds supplied by the caller.
struct BrightnessStepper {
    enum StopReason: Equatable { case reached, crossed, unavailable, noResponse, externalChange, limit, cancelled }
    enum Decision: Equatable { case up, down, wait, stop(StopReason) }
    private enum Direction { case up, down }
    private struct Pending {
        let baseline: Double
        let direction: Direction
        let sentAt: TimeInterval
        let revision: Int
    }

    private(set) var isActive = false
    private var target = 0.0
    private var revision = 0
    private var pending: Pending?
    private var attemptsWithoutProgress = 0
    private var stepsSent = 0
    private var startedAt: TimeInterval = 0
    private var blockedUntil: TimeInterval = 0

    private let feedbackTimeout: TimeInterval = 0.65
    private let cooldown: TimeInterval = 1.5
    private let maxSteps = 24
    private let maxDuration: TimeInterval = 8
    private let movementEpsilon = 0.002

    /// A pending event is never cancelled by a new drag: it must settle first,
    /// otherwise a reversal could race with the delayed previous key event.
    @discardableResult mutating func setTarget(_ value: Double, at now: TimeInterval) -> Bool {
        guard value.isFinite, now.isFinite, now >= blockedUntil else { return false }
        let bounded = min(1, max(0, value))
        if !isActive {
            isActive = true
            pending = nil
            attemptsWithoutProgress = 0
            stepsSent = 0
            startedAt = now
        }
        if abs(target - bounded) > 0.0001 { revision &+= 1 }
        target = bounded
        return true
    }

    mutating func cancel(at now: TimeInterval? = nil) -> Decision {
        if pending != nil, let now = now, now.isFinite { blockedUntil = max(blockedUntil, now + cooldown) }
        return stop(.cancelled)
    }

    mutating func tick(measured value: Double?, at now: TimeInterval) -> Decision {
        guard isActive else { return .stop(.cancelled) }
        guard now.isFinite, let value = value, value.isFinite, (0...1).contains(value) else {
            return stop(.unavailable)
        }
        guard now >= startedAt, now - startedAt <= maxDuration else { return stop(.limit) }

        if let event = pending {
            let delta = value - event.baseline
            if abs(delta) >= movementEpsilon {
                let movedInSentDirection = event.direction == .up ? delta > 0 : delta < 0
                guard movedInSentDirection else { return stop(.externalChange) }
                pending = nil
                attemptsWithoutProgress = 0
                // Stop after a quantized step crosses the original unchanged
                // target rather than oscillating forever between adjacent levels.
                if event.revision == revision {
                    let crossed = event.direction == .up ? event.baseline < target && value >= target : event.baseline > target && value <= target
                    if crossed { return stop(.crossed) }
                }
            } else if now - event.sentAt < feedbackTimeout {
                return .wait
            } else {
                pending = nil
                // A delayed key may still arrive. If the user changed the target
                // while it was in flight, stop rather than risk sending a new
                // opposing key before the old one is observed.
                if event.revision != revision {
                    blockedUntil = now + cooldown
                    return stop(.noResponse)
                }
                attemptsWithoutProgress += 1
                if attemptsWithoutProgress >= 2 {
                    blockedUntil = now + cooldown
                    return stop(.noResponse)
                }
            }
        }
        let tolerance = (target <= 0.005 || target >= 0.995) ? 0.005 : 0.012
        guard abs(target - value) > tolerance else { return stop(.reached) }
        guard stepsSent < maxSteps else { return stop(.limit) }
        let direction: Direction = target > value ? .up : .down
        pending = Pending(baseline: value, direction: direction, sentAt: now, revision: revision)
        stepsSent += 1
        return direction == .up ? .up : .down
    }

    private mutating func stop(_ reason: StopReason) -> Decision {
        isActive = false
        pending = nil
        return .stop(reason)
    }
}
