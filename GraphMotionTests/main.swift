import AppKit
import QuartzCore
final class RecordingLayer: CALayer {
    var recordedKey: String?
    var recordedAnimation: CAAnimation?
    override func add(_ anim: CAAnimation, forKey key: String?) { recordedKey = key; recordedAnimation = anim }
    func reset() { recordedKey = nil; recordedAnimation = nil }
}
let view = NSView(frame: NSRect(x:0,y:0,width:100,height:30)); view.wantsLayer = true
let layer = RecordingLayer(); view.layer = layer
let modes: Set<String> = ["cpu", "memory", "fade"]
func slide(_ from:String?, _ to:String, _ reduced:Bool = false) {
    TouchBarMotion.slideGraph(view,previous:from,next:to,available:modes,key:"graph",reduceMotion:reduced)
}
slide("cpu", "memory", true)
precondition(layer.recordedAnimation == nil)
slide("cpu", "memory")
var transition = layer.recordedAnimation as? CATransition
precondition(layer.recordedKey == "graph" && transition?.type == .push && transition?.subtype == .fromBottom)
precondition(abs((transition?.duration ?? 0) - 0.16) < 0.001)
layer.reset(); slide("memory", "cpu")
transition = layer.recordedAnimation as? CATransition
precondition(transition?.subtype == .fromTop)
layer.reset(); slide("cpu", "cpu")
precondition(layer.recordedAnimation == nil)
slide(nil, "cpu")
precondition(layer.recordedAnimation == nil)
slide("fade", "cpu")
precondition(layer.recordedAnimation == nil)
print("Graph directional transition tests passed")
