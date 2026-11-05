import Foundation
import Darwin
let args=CommandLine.arguments
let child=Process(); child.executableURL=URL(fileURLWithPath:args[1])
child.arguments=["monitor-parent",String(getpid()),args[2],args[3]]
try child.run()
Thread.sleep(forTimeInterval:5)
