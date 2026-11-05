import AppKit
import Foundation

final class FakeClient: TouchBarRequesting {
 var calls: [[String]] = []
 var response: IsolatedTouchBarClient.Result = .success(Data("{\"brightness\":0.4,\"automatic\":true}".utf8))
 func request(_ arguments: [String], completion: @escaping (IsolatedTouchBarClient.Result) -> Void) {
  calls.append(arguments)
  if arguments.first == "set" { completion(.success(Data())) } else { completion(response) }
 }
 func stop() { calls.append(["stop"]) }
}
func require(_ test:@autoclosure () -> Bool,_ message:String) { if !test() { fatalError(message) } }
let app = NSApplication.shared
let fake=FakeClient(), controller=TouchBarBrightnessMenu(client:fake)
let root=controller.makeItem(), submenu=root.submenu!
require(fake.calls.isEmpty,"construct must not access hardware")
controller.menuWillOpen(submenu)
require(fake.calls.count == 1 && fake.calls[0].first == "read","opening reads only")
submenu.performActionForItem(at:1)
require(fake.calls.count == 1 && fake.calls[0].first == "read","system mode never writes")
guard let slider = submenu.item(at:2)?.view?.subviews.compactMap({$0 as? NSSlider}).first else { fatalError("slider missing") }
require(!slider.isContinuous,"write only at release")
slider.doubleValue=50
_ = slider.sendAction(slider.action,to:slider.target)
require(fake.calls.count==3 && fake.calls[1].first == "set" && fake.calls[2].first == "read","one write then read")
require(fake.calls[1].count==3 && Double(fake.calls[1][1]) == 50,"validated payload")
submenu.performActionForItem(at:1)
require(fake.calls.count==3,"system mode after manual does not write")
controller.stop()
require(fake.calls.last == ["stop"],"stop does not write")
let stopped=FakeClient(); stopped.response = .indeterminate
let disabled=TouchBarBrightnessMenu(client:stopped), item=disabled.makeItem(), menu=item.submenu!
disabled.menuWillOpen(menu)
guard let control=menu.item(at:2)?.view?.subviews.compactMap({$0 as? NSSlider}).first else { fatalError("slider missing") }
require(!control.isEnabled,"timeout disables slider")
menu.performActionForItem(at:1)
require(stopped.calls.count == 1 && stopped.calls[0].first == "read","unknown state blocks further operations")
print("menu no-write and gating tests passed")
