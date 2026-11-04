import Foundation
import Darwin
let helper = CommandLine.arguments[1]
let fakeHelper = CommandLine.arguments[2]
let blockedHelper = CommandLine.arguments[3]
let closeHelper = CommandLine.arguments[4]
let cb = DispatchQueue(label: "callbacks", attributes: .concurrent)
func check(_ pass: @autoclosure () -> Bool, _ name: String) { if !pass() { fatalError(name) } }
func run(_ w: WorkerSession, _ timeout: Double = 3) -> WorkerSession.Reply {
    let gate = DispatchSemaphore(value: 0); let lock = NSLock(); var result: WorkerSession.Reply = .stopped
    w.run(timeout: timeout) { r in lock.lock(); result = r; lock.unlock(); gate.signal() }
    check(gate.wait(timeout: .now() + timeout + 5) == .success, "missing completion")
    lock.lock(); defer { lock.unlock() }; return result
}
func stop(_ w: WorkerSession) { let gate = DispatchSemaphore(value: 0); w.stop { gate.signal() }; check(gate.wait(timeout: .now() + 3) == .success, "stop") }
let source = "property counter : 0\non run\nset counter to counter + 1\nreturn {counter as string, \"cpu\"}\nend run"
let a = WorkerSession(executable: helper, source: .inline(source), callbackQueue: cb)
check(run(a) == .list(["1", "cpu"]), "first")
check(run(a) == .list(["2", "cpu"]), "state")
let b = WorkerSession(executable: helper, source: .inline("return \"日本語\""), callbackQueue: cb)
check(run(b) == .text("日本語"), "unicode")
let e = WorkerSession(executable: helper, source: .inline("return {}"), callbackQueue: cb)
check(run(e) == .list([]), "empty list")
let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mtmr-\(UUID()).applescript")
try "return {\"file\", \"image\"}".write(to: file, atomically: true, encoding: .utf8)
let f = WorkerSession(executable: helper, source: .file(file.path), callbackQueue: cb)
check(run(f) == .list(["file", "image"]), "file")
try? FileManager.default.removeItem(at: file)
let sentinel = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mtmr-once-\(UUID().uuidString)").path
let hanging = WorkerSession(executable: fakeHelper, source: .inline("hang-once:" + sentinel), callbackQueue: cb)
let finished = DispatchSemaphore(value: 0), busy = DispatchSemaphore(value: 0)
let l = NSLock(); var hr: WorkerSession.Reply = .stopped; var br: WorkerSession.Reply = .stopped
hanging.run(timeout: 1.5) { r in l.lock(); hr = r; l.unlock(); finished.signal() }
hanging.run(timeout: 1.5) { r in l.lock(); br = r; l.unlock(); busy.signal() }
check(busy.wait(timeout: .now() + 1) == .success && br == .busy, "busy")
let started = Date(); check(run(a, 1) == .list(["3", "cpu"]), "independence")
check(Date().timeIntervalSince(started) < 1, "other worker blocked")
check(finished.wait(timeout: .now() + 3) == .success && hr == .timeout, "timeout")
check(run(hanging, 1) == .cooldown, "cooldown")
Thread.sleep(forTimeInterval: 1.2)
check(run(hanging) == .text("recovered"), "automatic recovery with same source")
try? FileManager.default.removeItem(atPath: sentinel)
let replaced = DispatchSemaphore(value: 0)
hanging.replaceSource(.inline("recover")) { replaced.signal() }
check(replaced.wait(timeout: .now() + 3) == .success, "replace")
check(run(hanging) == .text("recovered"), "recovery after replacing source")
var ephemeral: WorkerSession? = WorkerSession(executable: fakeHelper, source: .inline("pid"), callbackQueue: cb)
let pidResult = run(ephemeral!)
guard case let .text(pidText) = pidResult, let pid = Int32(pidText) else { fatalError("PID test") }
ephemeral = nil
var exited = false
for _ in 0..<30 { if Darwin.kill(pid, 0) != 0 && errno == ESRCH { exited = true; break }; usleep(100_000) }
check(exited, "worker survived owner deinit")
let pidFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mtmr-burn-\(UUID().uuidString)")
let burn = WorkerSession(executable: fakeHelper, source: .inline("burn:" + pidFile.path), callbackQueue: cb)
check(run(burn, 1) == .timeout, "CPU-bound worker did not time out")
guard let pidText = try? String(contentsOf: pidFile, encoding: .utf8), let burningPID = Int32(pidText) else { fatalError("missing worker PID") }
var burningExited = false
for _ in 0..<30 { if Darwin.kill(burningPID, 0) != 0 && errno == ESRCH { burningExited = true; break }; usleep(100_000) }
check(burningExited, "CPU-bound worker survived timeout")
try? FileManager.default.removeItem(at: pidFile)
stop(burn)
let slow = WorkerSession(executable: helper, source: .inline("delay 7\nreturn \"ready\""), callbackQueue: cb)
check(run(slow, 15) == .text("ready"), "low-CPU waiting should not be stopped by CPU watchdog")
stop(slow)
let cpuLoop = WorkerSession(executable: helper, source: .inline("repeat\nend repeat"), callbackQueue: cb)
let loopStart = Date()
let loopResult = run(cpuLoop, 15)
switch loopResult { case .error: break; default: fatalError("CPU watchdog did not stop a busy AppleScript") }
check(Date().timeIntervalSince(loopStart) >= 3, "CPU loop exited before watchdog exercised")
check(Date().timeIntervalSince(loopStart) < 15, "CPU watchdog exceeded deadline")
stop(cpuLoop)
let denied = WorkerSession(executable: fakeHelper, source: .inline("deny"), callbackQueue: cb)
check(run(denied) == .error("automation denied"), "permission rejection")
Thread.sleep(forTimeInterval: 1.2)
check(run(denied) == .cooldown, "rejected permission should not prompt again")
stop(denied)
let blocked = WorkerSession(executable: blockedHelper, source: .inline(String(repeating: "x", count: 900_000)), callbackQueue: cb)
let blockingStart = Date()
check(run(blocked, 0.5) == .timeout, "large input did not time out")
check(Date().timeIntervalSince(blockingStart) < 2, "large pipe input blocked deadline")
let closes = WorkerSession(executable: closeHelper, source: .inline(String(repeating: "x", count: 900_000)), callbackQueue: cb)
let closedResult = run(closes, 0.8)
switch closedResult { case .error, .timeout: break; default: fatalError("unexpected closed pipe result") }
for w in [a, b, e, f, hanging, blocked, closes] { stop(w) }
print("PASS: state, strings, lists, files, timeout, backoff, recovery, concurrency")
