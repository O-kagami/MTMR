import Foundation
import Carbon
import Darwin

// A stuck interpreter must not outlive MTMR after a crash or force quit.
let parentPID = getppid()
if parentPID <= 1 { _exit(0) }
let parentWatch = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
parentWatch.schedule(deadline: .now() + 2, repeating: 2)
parentWatch.setEventHandler { if getppid() != parentPID { _exit(0) } }
parentWatch.resume()

// Permission dialogs consume almost no CPU; an interpreter error loop can
// consume a core indefinitely. Bound CPU time without killing idle permission waits.
let cpuLock = NSLock()
var cpuStart: Double?
func processCPUSeconds() -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}
func beginScriptWork() { cpuLock.lock(); cpuStart = processCPUSeconds(); cpuLock.unlock() }
func endScriptWork() { cpuLock.lock(); cpuStart = nil; cpuLock.unlock() }
let cpuWatch = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
cpuWatch.schedule(deadline: .now() + 2, repeating: 2)
cpuWatch.setEventHandler {
    cpuLock.lock(); let start = cpuStart; cpuLock.unlock()
    if let start = start, processCPUSeconds() - start > 5 { _exit(75) }
}
cpuWatch.resume()

func reply(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object), var line = String(data: data, encoding: .utf8) else { return }
    line.append("\n")
    FileHandle.standardOutput.write(Data(line.utf8))
}

var compiled: NSAppleScript?
while let line = readLine(strippingNewline: true) {
    guard let data = line.data(using: .utf8),
          let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let id = message["id"] as? Int,
          let operation = message["op"] as? String else { continue }
    if operation == "init" {
        beginScriptWork(); defer { endScriptWork() }
        var error: NSDictionary?
        let script: NSAppleScript?
        if let path = message["path"] as? String {
            script = NSAppleScript(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath), error: &error)
        } else if let source = message["source"] as? String, source.utf8.count <= 1_000_000 {
            script = NSAppleScript(source: source)
        } else { script = nil }
        guard let script = script else {
            reply(["id": id, "kind": "error", "reason": "invalid source"]); continue
        }
        guard script.compileAndReturnError(&error) else {
            reply(["id": id, "kind": "error", "reason": "compile failed"]); continue
        }
        compiled = script
        reply(["id": id, "kind": "ready"])
    } else if operation == "run" {
        beginScriptWork(); defer { endScriptWork() }
        guard let script = compiled else { reply(["id": id, "kind": "error", "reason": "not initialized"]); continue }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            let reason = (code == -1743 || code == -1744) ? "automation denied" : "execution failed"
            reply(["id": id, "kind": "error", "reason": reason]); continue
        }
        if result.descriptorType == typeAEList {
            let n = result.numberOfItems
            let values = n > 0 ? (1...n).map { result.atIndex($0)?.stringValue ?? "" } : []
            reply(["id": id, "kind": "list", "values": values])
        } else {
            reply(["id": id, "kind": "text", "value": result.stringValue ?? ""])
        }
    } else if operation == "stop" {
        reply(["id": id, "kind": "stopped"])
        break
    }
}
