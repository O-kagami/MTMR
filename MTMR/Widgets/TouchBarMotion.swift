import AppKit
import QuartzCore

/// Short, non-blocking fades for Touch Bar views. Call immediately before changing content.
enum TouchBarMotion {
    /// Only a real play/pause transition should animate; refreshes and errors do not.
    static func shouldFadePlayback(enabled: Bool, previous: String?, next: String) -> Bool {
        guard enabled, let previous = previous, previous != next else { return false }
        return (previous == "play" && next == "pause") || (previous == "pause" && next == "play")
    }

    /// Immediate touch feedback, independent of whether Spotify accepts a command.
    static func pulse(_ view: NSView, reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        guard !reduceMotion, let layer = view.layer else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1.0, 0.82, 1.0]
        animation.keyTimes = [0, 0.45, 1]
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "playbackTap")
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

    /// Move new content from the top while pushing old content down.
    static func slideDown(_ view: NSView, key: String, duration: CFTimeInterval = 0.16,
                          reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        guard !reduceMotion, let layer = view.layer else { return }
        let transition = CATransition()
        transition.type = .push
        transition.subtype = .fromTop
        transition.duration = duration
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(transition, forKey: key)
    }

    /// Replaces just the slider, leaving its neighbouring controls untouched.
    static func replaceSlider(in stack: NSStackView, old: NSView, new: NSView) {
        guard old !== new, let index = stack.arrangedSubviews.firstIndex(of: old) else { return }
        stack.removeArrangedSubview(old)
        old.removeFromSuperview()
        stack.insertArrangedSubview(new, at: index)
    }
}
