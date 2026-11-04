import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
func directionAndCrossing() {
    var s = BrightnessStepper()
    check(s.setTarget(0.75, at: 10), "valid target")
    check(s.tick(measured: 0.4, at: 10) == .up, "one up")
    check(s.tick(measured: 0.4, at: 10.3) == .wait, "wait for display")
    check(s.tick(measured: 0.55, at: 10.7) == .up, "next up only after progress")
    check(s.tick(measured: 0.80, at: 10.9) == .stop(.crossed), "do not oscillate after overshoot")
    check(!s.isActive, "finished")
}
func reversalWaitsForPendingEvent() {
    var s = BrightnessStepper()
    _ = s.setTarget(0.8, at: 10)
    check(s.tick(measured: 0.4, at: 10) == .up, "initial up")
    _ = s.setTarget(0.1, at: 10.1)
    check(s.tick(measured: 0.4, at: 10.2) == .wait, "no reversal before pending response")
    check(s.tick(measured: 0.5, at: 10.3) == .down, "reverse after response")
    check(s.tick(measured: 0.05, at: 10.5) == .stop(.crossed), "stop after crossing reversed target")
}
func reversalTimeoutStopsWithoutOppositeKey() {
    var s = BrightnessStepper()
    _ = s.setTarget(0.8, at: 40)
    check(s.tick(measured: 0.4, at: 40) == .up, "send initial key")
    _ = s.setTarget(0.1, at: 40.1)
    check(s.tick(measured: 0.4, at: 40.8) == .stop(.noResponse), "never reverse while old event may still arrive")
    check(!s.setTarget(0.1, at: 41), "cooldown after unresolved event")
}
func noResponseAndCooldown() {
    var s = BrightnessStepper()
    _ = s.setTarget(1, at: 20)
    check(s.tick(measured: 0.5, at: 20) == .up, "first try")
    check(s.tick(measured: 0.5, at: 20.3) == .wait, "pending")
    check(s.tick(measured: 0.5, at: 20.7) == .up, "one retry")
    check(s.tick(measured: 0.5, at: 21.4) == .stop(.noResponse), "stop when OS does not respond")
    check(!s.setTarget(0.8, at: 21.5), "cooldown prevents rapid retry storms")
    check(s.setTarget(0.8, at: 23.0), "retry allowed after cooldown")
}
func safeFailureAndBoundary() {
    var s = BrightnessStepper()
    check(!s.setTarget(.nan, at: 1), "reject nan target")
    _ = s.setTarget(-5, at: 1)
    check(s.tick(measured: 0, at: 1) == .stop(.reached), "clamp at zero")
    _ = s.setTarget(5, at: 2)
    check(s.tick(measured: 1, at: 2) == .stop(.reached), "clamp at one")
    _ = s.setTarget(0.8, at: 3)
    check(s.tick(measured: nil, at: 3) == .stop(.unavailable), "missing display emits no keys")
    _ = s.setTarget(0.8, at: 4)
    check(s.tick(measured: .nan, at: 4) == .stop(.unavailable), "nan measured value emits no keys")
    _ = s.setTarget(0.8, at: 5)
    check(s.tick(measured: 0.3, at: 5) == .up, "up before external change")
    check(s.tick(measured: 0.2, at: 5.2) == .stop(.externalChange), "opposite external movement stops")
}
func stepAndTimeCaps() {
    var s = BrightnessStepper()
    _ = s.setTarget(1, at: 0)
    var t = 0.0, value = 0.2
    for step in 0..<24 {
        check(s.tick(measured: value, at: t) == .up, "step \(step) should advance once")
        value += 0.003
        t += 0.16
    }
    check(s.tick(measured: value, at: t) == .stop(.limit), "bounded total key events")
    _ = s.setTarget(1, at: 10)
    check(s.tick(measured: 0.3, at: 10) == .up, "new session")
    check(s.tick(measured: 0.3, at: 18.1) == .stop(.limit), "time limit")
    _ = s.setTarget(0.8, at: 20)
    check(s.cancel() == .stop(.cancelled), "explicit cancel")
}
func jitterAndTargetChange() {
    var s = BrightnessStepper()
    _ = s.setTarget(0.75, at: 30)
    check(s.tick(measured: 0.4, at: 30) == .up, "first event")
    _ = s.setTarget(0.8, at: 30.1)
    check(s.tick(measured: 0.401, at: 30.15) == .wait, "tiny noise is not a response")
    _ = s.setTarget(0.2, at: 30.2)
    check(s.tick(measured: 0.5, at: 30.3) == .down, "latest target wins after delayed response")
}
func cancelledPendingEventCoolsDown() {
    var s = BrightnessStepper()
    _ = s.setTarget(0.8, at: 50)
    check(s.tick(measured: 0.4, at: 50) == .up, "send pending event")
    check(s.cancel(at: 50.1) == .stop(.cancelled), "cancel on mode switch")
    check(!s.setTarget(0.2, at: 50.5), "no new reversal while delayed event may arrive")
    check(s.setTarget(0.2, at: 51.7), "new adjustment accepted after cooldown")
}
directionAndCrossing()
reversalWaitsForPendingEvent()
reversalTimeoutStopsWithoutOppositeKey()
noResponseAndCooldown()
safeFailureAndBoundary()
stepAndTimeCaps()
jitterAndTargetChange()
cancelledPendingEventCoolsDown()
print("PASS: brightness feedback, reversal, bounds, cooldown, external changes and event limits")
