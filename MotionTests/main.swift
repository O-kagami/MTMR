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
TouchBarMotion.fade(view, key: "enabled", duration: 0.10, reduceMotion: false)
let animation = layer.recordedAnimation as? CATransition
precondition(layer.recordedKey == "enabled")
precondition(animation?.type == .fade)
precondition(abs((animation?.duration ?? 0) - 0.10) < 0.001)
print("Motion tests passed")

// Swapping the visible control must preserve its siblings and their order.
let toggle = NSView(), brightness = NSView(), volume = NSView(), label = NSView()
let stack = NSStackView(views: [toggle, brightness, label])
for _ in 0..<10 {
    TouchBarMotion.replaceSlider(in: stack, old: brightness, new: volume)
    precondition(stack.arrangedSubviews.count == 3)
    precondition(stack.arrangedSubviews[0] === toggle)
    precondition(stack.arrangedSubviews[1] === volume)
    precondition(stack.arrangedSubviews[2] === label)
    TouchBarMotion.replaceSlider(in: stack, old: volume, new: brightness)
    precondition(stack.arrangedSubviews[0] === toggle)
    precondition(stack.arrangedSubviews[1] === brightness)
    precondition(stack.arrangedSubviews[2] === label)
}
print("Rapid switch layout tests passed")
let fixedToggle = NSView(), fixedBrightness = NSView(), fixedVolume = NSView(), fixedLabel = NSView()
fixedToggle.widthAnchor.constraint(equalToConstant: 36).isActive = true
fixedBrightness.widthAnchor.constraint(equalToConstant: 80).isActive = true
fixedVolume.widthAnchor.constraint(equalToConstant: 80).isActive = true
fixedLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
let fixedStack = NSStackView(views: [fixedToggle, fixedBrightness, fixedLabel])
fixedStack.orientation = .horizontal
fixedStack.spacing = 8
let beforeWidth = fixedStack.fittingSize.width
TouchBarMotion.replaceSlider(in: fixedStack, old: fixedBrightness, new: fixedVolume)
let afterWidth = fixedStack.fittingSize.width
precondition(abs(beforeWidth - afterWidth) < 0.01, "switching should not alter item width")
print("Fixed-width switch layout test passed")

// Brightness is above volume: volume enters from below, brightness from above.
layer.recordedKey = nil
layer.recordedAnimation = nil
TouchBarMotion.slideLevel(view, showVolume: true, reduceMotion: true)
precondition(layer.recordedAnimation == nil, "Reduce Motion disables the transition")
TouchBarMotion.slideLevel(view, showVolume: true, reduceMotion: false)
let volumeTransition = layer.recordedAnimation as? CATransition
precondition(layer.recordedKey == "localLevelMode")
precondition(volumeTransition?.type == .push && volumeTransition?.subtype == .fromBottom)
precondition(abs((volumeTransition?.duration ?? 0) - 0.10) < 0.001)
TouchBarMotion.slideLevel(view, showVolume: false, reduceMotion: false)
let brightnessTransition = layer.recordedAnimation as? CATransition
precondition(brightnessTransition?.type == .push && brightnessTransition?.subtype == .fromTop)
for index in 0..<20 {
    let volume = index % 2 == 0
    TouchBarMotion.slideLevel(view, showVolume: volume, reduceMotion: false)
    let transition = layer.recordedAnimation as? CATransition
    precondition(layer.recordedKey == "localLevelMode", "rapid transitions reuse one animation key")
    precondition(transition?.subtype == (volume ? .fromBottom : .fromTop))
}
print("Bidirectional level transition tests passed")
