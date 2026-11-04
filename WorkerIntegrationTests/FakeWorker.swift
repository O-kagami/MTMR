import Foundation
import Darwin
var mode = ""
func reply(_ o: [String: Any]) { guard let bytes = try? JSONSerialization.data(withJSONObject: o) else { return }; FileHandle.standardOutput.write(bytes + Data([10])) }
while let line = readLine(), let bytes = line.data(using: .utf8), let msg = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any], let id = msg["id"] as? Int, let op = msg["op"] as? String {
    if op == "init" { mode = msg["source"] as? String ?? ""; reply(["id":id,"kind":"ready"]) }
    if op == "run" {
        if mode == "deny" { reply(["id":id,"kind":"error","reason":"automation denied"]); continue }
        if mode.hasPrefix("log:") {
            let path = String(mode.dropFirst(4))
            let handle = FileHandle(forWritingAtPath: path)!
            handle.seekToEndOfFile(); handle.write(Data("tap\n".utf8)); try? handle.close()
        }
        if mode.hasPrefix("burn:") {
            let path = String(mode.dropFirst(5))
            try? String(getpid()).write(toFile: path, atomically: true, encoding: .utf8)
            while true { _ = arc4random() }
        }
        if mode == "hang" { sleep(60) }
        if mode.hasPrefix("hang-once:") {
            let path = String(mode.dropFirst("hang-once:".count))
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: Data())
                sleep(60)
            }
        }
        reply(["id":id,"kind":"text","value":mode == "pid" ? String(getpid()) : "recovered"])
    }
}
