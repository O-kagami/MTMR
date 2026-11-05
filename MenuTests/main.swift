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

let autoClient = FakeClient(), autoMenu = TouchBarBrightnessMenu(client: autoClient)
let autoRoot = autoMenu.makeItem(), autoSubmenu = autoRoot.submenu!
autoMenu.observeDisplayBrightness(0.50)
autoMenu.observeDisplayBrightness(0.50)
require(autoClient.calls.isEmpty, "startup and unchanged brightness must not write")
autoMenu.menuWillOpen(autoSubmenu)
guard let manualSlider = autoSubmenu.item(at: 2)?.view?.subviews.compactMap({ $0 as? NSSlider }).first else { fatalError("slider missing") }
manualSlider.doubleValue = 25
_ = manualSlider.sendAction(manualSlider.action, to: manualSlider.target)
let manualCount = autoClient.calls.count
autoMenu.observeDisplayBrightness(0.50)
require(autoClient.calls.count == manualCount, "unchanged display must preserve a manual Touch Bar adjustment")
autoMenu.observeDisplayBrightness(0.70)
require(autoClient.calls.count == manualCount + 1 && autoClient.calls.last?.first == "set" && abs((Double(autoClient.calls.last![1]) ?? 0) - 70) < 0.01, "a display change synchronizes the Touch Bar")
autoMenu.observeDisplayBrightness(0)
require(abs((Double(autoClient.calls.last![1]) ?? 0) - 5) < 0.01, "minimum uses the safe Touch Bar limit")
let validCount = autoClient.calls.count
autoMenu.observeDisplayBrightness(.nan)
autoMenu.observeDisplayBrightness(1.1)
require(autoClient.calls.count == validCount, "invalid readings must not write")
autoMenu.stop()

final class DeferredClient: TouchBarRequesting {
 var calls: [[String]] = []
 var completions: [(IsolatedTouchBarClient.Result) -> Void] = []
 func request(_ arguments: [String], completion: @escaping (IsolatedTouchBarClient.Result) -> Void) { calls.append(arguments); completions.append(completion) }
 func stop() {}
 func finish(_ result: IsolatedTouchBarClient.Result) { completions.removeFirst()(result) }
}
let queuedClient = DeferredClient(), queuedMenu = TouchBarBrightnessMenu(client: queuedClient)
queuedMenu.observeDisplayBrightness(0.2)
queuedMenu.observeDisplayBrightness(0.3)
queuedMenu.observeDisplayBrightness(0.4)
queuedMenu.observeDisplayBrightness(0.8)
require(queuedClient.calls.count == 1, "writes must not overlap")
queuedClient.finish(.success(Data()))
require(queuedClient.calls.count == 2 && abs((Double(queuedClient.calls[1][1]) ?? 0) - 80) < 0.01, "only latest queued display value is sent")
queuedClient.finish(.indeterminate)
queuedMenu.observeDisplayBrightness(0.9)
require(queuedClient.calls.count == 2, "a timed-out helper blocks subsequent writes")
queuedMenu.stop()
print("display synchronization and manual override tests passed")
