import AppKit
import QuartzCore

/// Short, non-blocking fades for Touch Bar views. Call immediately before changing content.
enum TouchBarMotion {
    /// Only a confirmed play/pause state change should morph.
    static func shouldMorphPlayback(enabled: Bool, previous: String?, next: String) -> Bool {
        guard enabled, let previous = previous, previous != next else { return false }
        return (previous == "play" && next == "pause") || (previous == "pause" && next == "play")
    }

    static func fade(_ view: NSView, key: String, duration: CFTimeInterval = 0.16,
                     reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        guard !reduceMotion,
              let layer = view.layer else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = duration
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(transition, forKey: key)
    }

    /// Graph contents also refresh under an unchanged key; animate only mode changes.
    static func isGraphModeChange(previous: String?, next: String, available: Set<String>) -> Bool {
        guard let previous = previous, previous != next else { return false }
        let modes: Set<String> = ["cpu", "memory"]
        return modes.isSubset(of: available) && modes.contains(previous) && modes.contains(next)
    }

    /// CPU is above memory: the incoming graph enters from its relative position.
    static func slideGraph(_ view: NSView, previous: String?, next: String, available: Set<String>,
                           key: String, duration: CFTimeInterval = 0.16,
                           reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        guard !reduceMotion, isGraphModeChange(previous: previous, next: next, available: available),
              let layer = view.layer else { return }
        let transition = CATransition()
        transition.type = .push
        transition.subtype = next == "memory" ? .fromBottom : .fromTop
        transition.duration = duration
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(transition, forKey: key)
    }

    /// Brightness is above volume. Entering volume brings it from below;
    /// returning to brightness brings it from above. Existing content moves
    /// in the opposite direction, like moving through a vertical list.
    static func slideLevel(_ view: NSView, showVolume: Bool, duration: CFTimeInterval = 0.10,
                           reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        guard !reduceMotion, let layer = view.layer else { return }
        let transition = CATransition()
        transition.type = .push
        transition.subtype = showVolume ? .fromBottom : .fromTop
        transition.duration = duration
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(transition, forKey: "localLevelMode")
    }

    /// Replaces just the slider, leaving its neighbouring controls untouched.
    static func replaceSlider(in stack: NSStackView, old: NSView, new: NSView) {
        guard old !== new, let index = stack.arrangedSubviews.firstIndex(of: old) else { return }
        stack.removeArrangedSubview(old)
        old.removeFromSuperview()
        stack.insertArrangedSubview(new, at: index)
    }
}

/// Native vector transition for a play triangle and a two-bar pause symbol.
/// Only manages temporary layers; the caller owns the authoritative image/state.
final class PlaybackMorphController {
    private var layers: [CAShapeLayer] = []
    private var finishWork: DispatchWorkItem?
    private var generation: UInt64 = 0
    private(set) var currentImageRect: CGRect?
    private let duration: CFTimeInterval = 0.14

    func cancel() {
        generation &+= 1
        finishWork?.cancel()
        finishWork = nil
        layers.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
        layers.removeAll()
        currentImageRect = nil
    }

    @discardableResult
    func animate(from: String?, to: String, in view: NSView, imageRect: CGRect,
                 reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                 completion: @escaping () -> Void) -> Bool {
        guard TouchBarMotion.shouldMorphPlayback(enabled: true, previous: from, next: to),
              !reduceMotion, let previous = from, let host = view.layer,
              imageRect.width.isFinite, imageRect.height.isFinite,
              imageRect.minX.isFinite, imageRect.minY.isFinite,
              imageRect.width > 0, imageRect.height > 0 else {
            cancel()
            return false
        }
        // If a new confirmed state arrives mid-morph, continue from what is
        // currently visible, rather than allowing an old completion to win.
        let previousPaths = currentImageRect == imageRect && layers.count == 2
            ? layers.map { $0.presentation()?.path ?? $0.path } : []
        let fromPaths = previousPaths.count == 2 && previousPaths.allSatisfy { $0 != nil }
            ? previousPaths.compactMap { $0 } : Self.paths(for: previous, in: imageRect)
        let toPaths = Self.paths(for: to, in: imageRect)
        guard fromPaths.count == 2, toPaths.count == 2 else { cancel(); return false }
        cancel()
        currentImageRect = imageRect
        let token = generation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in 0..<2 {
            let shape = CAShapeLayer()
            shape.frame = view.bounds
            shape.fillColor = NSColor.white.cgColor
            shape.path = toPaths[index]
            host.addSublayer(shape)
            let motion = CABasicAnimation(keyPath: "path")
            motion.fromValue = fromPaths[index]
            motion.toValue = toPaths[index]
            motion.duration = duration
            motion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shape.add(motion, forKey: "playbackMorph")
            layers.append(shape)
        }
        CATransaction.commit()
        let finish = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == token else { return }
            self.cancel()
            completion()
        }
        finishWork = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: finish)
        return true
    }

    /// Both shapes have identical path commands so Core Animation interpolates
    /// matching points, including the seam between the two play-triangle pieces.
    static func paths(for mode: String, in rect: CGRect) -> [CGPath] {
        guard mode == "play" || mode == "pause" else { return [] }
        let polygons: [[CGPoint]]
        if mode == "play" {
            polygons = [
                [CGPoint(x: 8, y: 4), CGPoint(x: 12, y: 20.0/3), CGPoint(x: 12, y: 52.0/3), CGPoint(x: 8, y: 20)],
                [CGPoint(x: 12, y: 20.0/3), CGPoint(x: 20, y: 12), CGPoint(x: 20, y: 12), CGPoint(x: 12, y: 52.0/3)]
            ]
        } else {
            polygons = [
                [CGPoint(x: 6, y: 5), CGPoint(x: 10, y: 5), CGPoint(x: 10, y: 19), CGPoint(x: 6, y: 19)],
                [CGPoint(x: 14, y: 5), CGPoint(x: 18, y: 5), CGPoint(x: 18, y: 19), CGPoint(x: 14, y: 19)]
            ]
        }
        let size = min(rect.width, rect.height)
        let left = rect.midX - size / 2
        let bottom = rect.midY - size / 2
        let scale = size / 24
        return polygons.map { polygon in
            let points = polygon.map { CGPoint(x: left + $0.x * scale, y: bottom + $0.y * scale) }
            let radius: CGFloat = mode == "pause" ? 0.75 * scale : 0
            func toward(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
                let dx = q.x - p.x, dy = q.y - p.y
                let length = hypot(dx, dy)
                guard length > 0 else { return p }
                let distance = min(radius, length / 2)
                return CGPoint(x: p.x + dx / length * distance, y: p.y + dy / length * distance)
            }
            let result = CGMutablePath()
            result.move(to: toward(points[0], points[3]))
            for i in points.indices {
                let p = points[i], previous = points[(i + 3) % 4], next = points[(i + 1) % 4]
                result.addLine(to: toward(p, previous))
                result.addQuadCurve(to: toward(p, next), control: p)
            }
            result.closeSubpath()
            return result
        }
    }
}
