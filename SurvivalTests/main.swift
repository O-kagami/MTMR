import Foundation
import Darwin
func require(_ condition: @autoclosure () -> Bool,_ message:String) { if !condition() { fatalError(message) } }
let fake=URL(fileURLWithPath:CommandLine.arguments[1]), parentURL=URL(fileURLWithPath:CommandLine.arguments[2])
let dir=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("mtmr-survival-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
let ignoredPID=dir.appendingPathComponent("ignore.pid"), ready=dir.appendingPathComponent("ready"), marker=dir.appendingPathComponent("unexpected")
let client=IsolatedTouchBarClient(helper:fake,timeout:0.5)
client.request(["ignore-term",ignoredPID.path]) { result in
 guard case .indeterminate=result else { fatalError("timeout should be indeterminate") }
 DispatchQueue.main.asyncAfter(deadline:.now()+0.8) {
  guard let text=try? String(contentsOf:ignoredPID,encoding:.utf8), let pid=Int32(text) else { fatalError("fake did not start") }
  errno=0; let exists=kill(pid,0)
  require(exists == -1 && errno == ESRCH,"SIGKILL escalation must reap unresponsive helper")
  let parent=Process(); parent.executableURL=parentURL; parent.arguments=[fake.path,ready.path,marker.path]
  try! parent.run()
  DispatchQueue.global().async {
   let until=Date().addingTimeInterval(2)
   while !FileManager.default.fileExists(atPath:ready.path) && Date()<until { Thread.sleep(forTimeInterval:0.02) }
   guard let text=try? String(contentsOf:ready,encoding:.utf8), let child=Int32(text) else { fatalError("monitor fake did not start") }
   _=kill(parent.processIdentifier,SIGKILL)
   parent.waitUntilExit()
   Thread.sleep(forTimeInterval:0.8)
   errno=0; let alive=kill(child,0)
   require(alive == -1 && errno == ESRCH,"helper must stop after parent killed")
   require(!FileManager.default.fileExists(atPath:marker.path),"orphan must not do delayed action")
   try? FileManager.default.removeItem(at:dir)
   print("timeout and parent-death process tests passed"); exit(0)
  }
 }
}
DispatchQueue.main.asyncAfter(deadline:.now()+8) { fatalError("test deadline") }
RunLoop.main.run()
