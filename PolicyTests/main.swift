import Foundation
func check(_ value:@autoclosure () -> Bool, _ reason:String) { if !value() { fatalError(reason) } }
for number in [Double.nan, -.infinity, -1, 0, 0.049, 1.001, .infinity] {
    check(TemporaryBrightnessPolicy.payload(number) == nil, "invalid \(number)")
}
for number in [0.05, 0.5, 1.0] {
    let payload = TemporaryBrightnessPolicy.payload(number)!
    check(payload.count == 3, "no automatic setting")
    check(payload["Brightness"] as? Double == number, "correct value")
    check(payload["Commit"] as? Bool == false, "commit disabled")
    check(payload["CommitType"] as? Int == 0, "commit type")
}
print("temporary payload validation passed")
