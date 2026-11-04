import AppKit
import QuartzCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
expect(!TouchBarMotion.shouldFadePlayback(enabled: false, previous: "play", next: "pause"), "opt-in")
expect(!TouchBarMotion.shouldFadePlayback(enabled: true, previous: nil, next: "play"), "initial image")
expect(!TouchBarMotion.shouldFadePlayback(enabled: true, previous: "play", next: "play"), "unchanged image")
expect(!TouchBarMotion.shouldFadePlayback(enabled: true, previous: "play", next: "unavailable"), "unavailable")
expect(TouchBarMotion.shouldFadePlayback(enabled: true, previous: "play", next: "pause"), "play to pause")
expect(TouchBarMotion.shouldFadePlayback(enabled: true, previous: "pause", next: "play"), "pause to play")
final class RecordingLayer: CALayer {
    var lastKey: String?
    var lastAnimation: CAAnimation?
    override func add(_ animation: CAAnimation, forKey key: String?) {
        lastKey = key
        lastAnimation = animation
    }
}
let v = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 30))
v.wantsLayer = true
let layer = RecordingLayer()
v.layer = layer
TouchBarMotion.pulse(v, reduceMotion: true)
expect(layer.lastAnimation == nil, "reduced motion pulse")
TouchBarMotion.pulse(v, reduceMotion: false)
expect(layer.lastKey == "playbackTap" && (layer.lastAnimation?.duration ?? 1) <= 0.15, "short pulse")
layer.lastKey = nil
layer.lastAnimation = nil
TouchBarMotion.fade(v, key: "playbackState", duration: 0.12, reduceMotion: true)
expect(layer.lastAnimation == nil, "reduced motion fade")
TouchBarMotion.fade(v, key: "playbackState", duration: 0.12, reduceMotion: false)
expect(layer.lastKey == "playbackState" && layer.lastAnimation is CATransition, "transition fade")
print("Playback motion tests passed")
