import Foundation
import Darwin

// One request per process. Monitor the parent so a hung helper does not remain
// after MTMR exits; this cannot undo a request already accepted by the OS.
let arguments = CommandLine.arguments
func output(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value),
          let text = String(data: data, encoding: .utf8) else { return }
    print(text)
}
guard arguments.count >= 3 else { exit(64) }
let command = arguments[1]
let parentArgument = command == "read" && arguments.count == 3 ? arguments[2] :
    (command == "set" && arguments.count == 4 ? arguments[3] : "")
guard let owner = Int32(parentArgument), owner > 1, getppid() == owner else { exit(64) }
guard let monitor = watchParent(owner) else { exit(75) }
// A global reference keeps the source alive until this one-shot helper exits.
_ = monitor
if command == "read" {
    guard let snapshot = CoreBrightnessTouchBarDevice().read(), getppid() == owner else { exit(1) }
    output(["automatic": snapshot.automatic, "brightness": snapshot.brightness])
    exit(0)
}
if command == "set", let percent = Double(arguments[2]), percent.isFinite, (5...100).contains(percent), getppid() == owner {
    let ok = CoreBrightnessTouchBarDevice().setTemporary(percent / 100, owner: owner)
    exit(ok ? 0 : 1)
}
exit(64)
