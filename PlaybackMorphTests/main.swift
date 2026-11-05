import AppKit
import QuartzCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func types(_ path: CGPath) -> [CGPathElementType] {
    var result: [CGPathElementType] = []
    path.applyWithBlock { element in result.append(element.pointee.type) }
    return result
}
let rect = CGRect(x: 3, y: 2, width: 24, height: 24)
let play = PlaybackMorphController.paths(for: "play", in: rect)
let pause = PlaybackMorphController.paths(for: "pause", in: rect)
expect(play.count == 2 && pause.count == 2, "two corresponding pieces")
expect(zip(play,pause).allSatisfy { types($0) == types($1) }, "matching path commands")
expect(!play[0].boundingBoxOfPath.equalTo(pause[0].boundingBoxOfPath), "different target geometry")
expect(PlaybackMorphController.paths(for: "unknown", in: rect).isEmpty, "unknown state rejected")
let view = NSView(frame: CGRect(x: 0, y: 0, width: 32, height: 30))
view.wantsLayer = true
let controller = PlaybackMorphController()
var completions: [String] = []
expect(!controller.animate(from: nil, to: "play", in: view, imageRect: rect, reduceMotion: false) { completions.append("initial") }, "initial state does not animate")
expect(!controller.animate(from: "play", to: "play", in: view, imageRect: rect, reduceMotion: false) { completions.append("same") }, "same state does not animate")
expect(!controller.animate(from: "play", to: "unavailable", in: view, imageRect: rect, reduceMotion: false) { completions.append("unavailable") }, "error does not animate")
expect(!controller.animate(from: "play", to: "pause", in: view, imageRect: rect, reduceMotion: true) { completions.append("reduced") }, "reduce motion")
expect(controller.animate(from: "play", to: "pause", in: view, imageRect: rect, reduceMotion: false) { completions.append("stale") }, "forward morph")
expect((view.layer?.sublayers ?? []).count == 2, "two morph layers")
expect((view.layer?.sublayers ?? []).allSatisfy { $0.animation(forKey: "playbackMorph") is CABasicAnimation }, "path animation")
expect(controller.animate(from: "pause", to: "play", in: view, imageRect: rect, reduceMotion: false) { completions.append("latest") }, "reverse while active")
expect((view.layer?.sublayers ?? []).count == 2, "no leaked morph layers")
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
expect(completions == ["latest"], "stale completion canceled")
expect((view.layer?.sublayers ?? []).isEmpty, "layers removed")
expect(controller.currentImageRect == nil, "state cleared")
expect(controller.animate(from: "play", to: "pause", in: view, imageRect: rect, reduceMotion: false) { completions.append("cancelled") }, "cancel test setup")
controller.cancel()
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
expect(completions == ["latest"], "cancel suppresses completion")
print("Playback morph tests passed")
