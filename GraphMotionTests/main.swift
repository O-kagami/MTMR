import AppKit
import QuartzCore
final class RecordingLayer: CALayer {
    var recordedKey: String?
    var recordedAnimation: CAAnimation?
    override func add(_ anim: CAAnimation, forKey key: String?) { recordedKey = key; recordedAnimation = anim }
}
let view = NSView(frame:NSRect(x:0,y:0,width:100,height:30)); view.wantsLayer = true
let layer = RecordingLayer(); view.layer = layer
TouchBarMotion.slideDown(view, key:"reduced", reduceMotion:true)
precondition(layer.recordedAnimation == nil)
TouchBarMotion.slideDown(view, key:"enabled", reduceMotion:false)
let transition = layer.recordedAnimation as? CATransition
precondition(layer.recordedKey == "enabled" && transition?.type == .push && transition?.subtype == .fromTop)
precondition(abs((transition?.duration ?? 0) - 0.16) < 0.001)
let modes:Set<String>=["cpu","memory","fade"]
precondition(TouchBarMotion.isGraphModeChange(previous:"cpu",next:"memory",available:modes))
precondition(TouchBarMotion.isGraphModeChange(previous:"memory",next:"cpu",available:modes))
precondition(!TouchBarMotion.isGraphModeChange(previous:"cpu",next:"cpu",available:modes))
precondition(!TouchBarMotion.isGraphModeChange(previous:nil,next:"cpu",available:modes))
precondition(!TouchBarMotion.isGraphModeChange(previous:"fade",next:"cpu",available:modes))
print("Graph transition tests passed")
