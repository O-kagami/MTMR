import AppKit
import QuartzCore

final class RecordingLayer: CALayer {
    var recordedKey: String?
    var recordedAnimation: CAAnimation?
    override func add(_ anim: CAAnimation, forKey key: String?) {
        recordedKey = key
        recordedAnimation = anim
    }
}
let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
view.wantsLayer = true
let layer = RecordingLayer()
view.layer = layer
TouchBarMotion.fade(view, key: "reduced", reduceMotion: true)
precondition(layer.recordedAnimation == nil)
TouchBarMotion.fade(view, key: "enabled", reduceMotion: false)
let animation = layer.recordedAnimation as? CATransition
precondition(layer.recordedKey == "enabled")
precondition(animation?.type == .fade)
precondition(abs((animation?.duration ?? 0) - 0.16) < 0.001)
print("Motion tests passed")
