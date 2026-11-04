import Foundation
func check(_ c: @autoclosure () -> Bool, _ message: String) { precondition(c(), message) }
var sent: [Float] = []
let ok: (Float) -> Int32 = { sent.append($0); return 0 }
check(BrightnessWriter.apply(.nan, write: ok) == .invalid, "reject non-finite")
check(BrightnessWriter.apply(-0.1, write: ok) == .invalid, "reject negative")
check(BrightnessWriter.apply(1.1, write: ok) == .invalid, "reject above one")
check(sent.isEmpty, "invalid values must never reach the writer")
check(BrightnessWriter.apply(0.3, write: nil) == .unavailable, "missing writer")
check(BrightnessWriter.apply(0, write: ok) == .accepted, "zero supported")
check(BrightnessWriter.apply(1, write: ok) == .accepted, "one supported")
check(sent == [0, 1], "endpoints forwarded")
check(BrightnessWriter.apply(0.5, write: { _ in -42 }) == .failed(-42), "propagate failure")
print("BrightnessWriter tests passed")
