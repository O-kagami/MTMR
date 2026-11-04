import AppKit

/// Identifies only the two edges; the native slider retains all interior tracking.
enum SliderEdgePolicy {
    enum Edge { case minimum, maximum }
    static func edge(startX: CGFloat, endX: CGFloat, bounds: CGRect) -> Edge? {
        guard startX.isFinite, endX.isFinite, bounds.width.isFinite, bounds.width > 0,
              bounds.minX.isFinite, bounds.maxX.isFinite,
              abs(endX - startX) >= 2 else { return nil }
        let margin = min(6, bounds.width / 4)
        if endX <= bounds.minX + margin { return .minimum }
        if endX >= bounds.maxX - margin { return .maximum }
        return nil
    }
}

/// One direct finger only. A second finger permanently cancels this sequence.
struct SliderSwipeSession {
    private var startX: CGFloat?
    private var cancelled = false
    mutating func begin(x: CGFloat, activeTouches: Int) {
        guard !cancelled, startX == nil, activeTouches == 1, x.isFinite else { cancel(); return }
        startX = x
    }
    mutating func move(activeTouches: Int) {
        if activeTouches != 1 { cancel() }
    }
    mutating func end(x: CGFloat, remainingTouches: Int, bounds: CGRect) -> SliderEdgePolicy.Edge? {
        defer { reset() }
        guard !cancelled, remainingTouches == 0, let startX = startX else { return nil }
        return SliderEdgePolicy.edge(startX: startX, endX: x, bounds: bounds)
    }
    mutating func cancel() { startX = nil; cancelled = true }
    mutating func reset() { startX = nil; cancelled = false }
}

/// Passively observes direct Touch Bar touches and never recognizes the gesture,
/// so normal slider tracking continues to handle the whole swipe.
final class SliderEdgeObserver: NSGestureRecognizer {
    private weak var slider: NSSlider?
    private var session = SliderSwipeSession()
    init(slider: NSSlider) {
        self.slider = slider
        super.init(target: nil, action: nil)
        allowedTouchTypes = .direct
        delaysPrimaryMouseButtonEvents = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func touchesBegan(with event: NSEvent) {
        guard let slider = slider, slider.isEnabled else { session.cancel(); return }
        let touches = event.touches(matching: .began, in: slider)
        let active = event.touches(matching: .touching, in: nil).count
        guard touches.count == 1, let touch = touches.first else { session.cancel(); return }
        session.begin(x: touch.location(in: slider).x, activeTouches: active)
        if active != 1 { state = .failed }
    }
    override func touchesMoved(with event: NSEvent) {
        let active = event.touches(matching: .touching, in: nil).count
        session.move(activeTouches: active)
        if active != 1 { state = .failed }
    }
    override func touchesEnded(with event: NSEvent) {
        defer { session.reset(); state = .failed }
        guard let slider = slider, slider.isEnabled else { return }
        let touches = event.touches(matching: .ended, in: slider)
        let remaining = event.touches(matching: .touching, in: nil).count
        guard touches.count == 1, let touch = touches.first,
              let edge = session.end(x: touch.location(in: slider).x, remainingTouches: remaining, bounds: slider.bounds) else { return }
        // Apply after AppKit has finished native slider tracking for this event.
        DispatchQueue.main.async { [weak slider] in
            guard let slider = slider, slider.isEnabled else { return }
            let target = edge == .minimum ? slider.minValue : slider.maxValue
            guard slider.doubleValue != target else { return }
            slider.doubleValue = target
            slider.sendAction(slider.action, to: slider.target)
        }
    }
    override func touchesCancelled(with event: NSEvent) { session.cancel(); state = .failed }
    override func reset() { super.reset(); session.reset() }
}
