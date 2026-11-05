import Foundation
import Darwin
let client=IsolatedTouchBarClient(helper:URL(fileURLWithPath:"/private/tmp/mtmr-touchbar-temp-helper"),timeout:2)
client.request(["read",String(getpid())]) { reply in
 switch reply {
 case .success(let data):
  guard let value = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any], value["brightness"] is NSNumber else { exit(1) }
  print("isolated read available"); exit(0)
 default: print("isolated read unavailable"); exit(1)
 }
}
RunLoop.main.run()
