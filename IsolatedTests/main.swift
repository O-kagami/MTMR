import Foundation
let fake=URL(fileURLWithPath:CommandLine.arguments[1])
func require(_ value:@autoclosure () -> Bool,_ message:String) { if !value() { fatalError(message) } }
let client=IsolatedTouchBarClient(helper:fake,timeout:0.2)
var callbacks=0
client.request(["ok"]) { result in
 guard case let .success(data)=result else { fatalError("success: \(result)") }
 require(String(data:data,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines)=="ok","output")
 client.request(["fail"]) { result in
  guard case .failed(7)=result else { fatalError("failure status") }
  client.request(["delay"]) { result in
   callbacks += 1
   guard case .indeterminate=result else { fatalError("timeout") }
   client.stop() // timeout then stop must not repeat completion
   client.request(["ok"]) { result in
    guard case .indeterminate=result else { fatalError("blocked after timeout") }
    DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
     require(callbacks == 1,"timeout callback exactly once")
     let other=IsolatedTouchBarClient(helper:fake,timeout:2)
     other.request(["delay"]) { result in
      guard case .indeterminate=result else { fatalError("cancel result") }
      other.request(["ok"]) { result in
       guard case .indeterminate=result else { fatalError("blocked after stop") }
       print("isolated process tests passed"); exit(0)
      }
     }
     DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { other.stop() }
    }
   }
  }
  client.request(["ok"]) { result in guard case .busy=result else { fatalError("single in-flight") } }
 }
}
DispatchQueue.main.asyncAfter(deadline:.now()+8) { fatalError("test deadline") }
RunLoop.main.run()
