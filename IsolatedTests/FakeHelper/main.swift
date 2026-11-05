import Foundation
import Darwin
let args=CommandLine.arguments
let mode = args.dropFirst().first ?? ""
if mode == "ok" { print("ok"); exit(0) }
if mode == "fail" { exit(7) }
if mode == "delay" { Thread.sleep(forTimeInterval: 3); print("late"); exit(0) }
if mode == "ignore-term", args.count == 3 {
 signal(SIGTERM, SIG_IGN)
 try! String(getpid()).write(toFile:args[2],atomically:true,encoding:.utf8)
 Thread.sleep(forTimeInterval: 5); exit(0)
}
if mode == "monitor-parent", args.count == 5, let owner=Int32(args[2]), let monitor=watchParent(owner) {
 _ = monitor
 try! String(getpid()).write(toFile:args[3],atomically:true,encoding:.utf8)
 Thread.sleep(forTimeInterval: 2)
 try! "unexpected".write(toFile:args[4],atomically:true,encoding:.utf8)
 exit(0)
}
exit(64)
