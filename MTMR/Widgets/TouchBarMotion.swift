import AppKit
import QuartzCore

/// Short, non-blocking fades for Touch Bar views. Call immediately before changing content.
enum TouchBarMotion {
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
}
