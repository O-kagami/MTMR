import Foundation
let worker = CommandLine.arguments[1]
let log = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mtmr-action-\(UUID().uuidString)")
FileManager.default.createFile(atPath: log.path, contents: Data())
let runner = ScriptActionRunner(session: WorkerSession(executable: worker, source: .inline("log:" + log.path)))
let start = Date()
runner.invoke(); runner.invoke(); runner.invoke()
precondition(Date().timeIntervalSince(start) < 0.5, "Action unexpectedly blocked UI")
let deadline = Date().addingTimeInterval(8)
var count = 0
while Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    count = text.split(separator: "\n").count
    if count >= 3 { break }
}
precondition(count == 3, "Multiple taps must be preserved and run serially")
try? FileManager.default.removeItem(at: log)
print("PASS: tap actions return immediately and preserve queued taps")
