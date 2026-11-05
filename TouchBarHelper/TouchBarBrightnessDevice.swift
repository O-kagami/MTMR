import Foundation
import ObjectiveC
import Darwin

/// Uses private macOS frameworks. All methods fail closed unless the display
/// advertises itself as a Touch Bar (type 3). Nothing is written by init/read.
final class CoreBrightnessTouchBarDevice: TouchBarBrightnessDevice {
    private let brightness: NSObject?
    private let dimming: NSObject?
    private let getID = NSSelectorFromString("getDFRDisplayID")
    private let setProperty = NSSelectorFromString("setProperty:withKey:andDisplay:")
    private let getProperty = NSSelectorFromString("copyPropertyForKey:andDisplay:")
    init() {
        let c = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        let d = dlopen("/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness", RTLD_LAZY)
        brightness = c.flatMap { _ in (NSClassFromString("BrightnessSystemClient") as? NSObject.Type)?.init() }
        dimming = d.flatMap { _ in (NSClassFromString("DFRBrightnessClient") as? NSObject.Type)?.init() }
    }
    private func matches(_ client: NSObject, _ selector: Selector, _ signature: String) -> Bool {
        guard let method = class_getInstanceMethod(type(of: client), selector),
              let encoding = method_getTypeEncoding(method) else { return false }
        return String(cString: encoding) == signature
    }
    private func displayID() -> UInt64? {
        guard let client = dimming, matches(client, getID, "i16@0:8"),
              let imp = client.method(for: getID) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Int32
        let result = unsafeBitCast(imp, to: Fn.self)(client, getID)
        guard result > 0 else { return nil }
        let id = UInt64(result)
        guard let type = property("CBDisplayType", id: id) as? NSNumber, type.intValue == 3 else { return nil }
        return id
    }
    private func property(_ name: String, id: UInt64) -> AnyObject? {
        guard let client = brightness, matches(client, getProperty, "@32@0:8@16Q24"),
              let imp = client.method(for: getProperty) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, UInt64) -> Unmanaged<AnyObject>?
        return unsafeBitCast(imp, to: Fn.self)(client, getProperty, name as NSString, id)?.takeRetainedValue()
    }
    // One uncommitted request, never changes DisplayBrightnessAuto. The
    // semantics are undocumented and do not guarantee the OS will retain it.
    func setTemporary(_ value: Double, owner: pid_t) -> Bool {
        guard getppid() == owner, let payload = TemporaryBrightnessPolicy.payload(value),
              let id = displayID(), let client = brightness,
              matches(client, setProperty, "B40@0:8@16@24Q32"),
              let imp = client.method(for: setProperty), getppid() == owner else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, UInt64) -> Bool
        let props = payload as NSDictionary
        return unsafeBitCast(imp, to: Fn.self)(client, setProperty, props, "DisplayBrightness" as NSString, id)
    }
    func read() -> TouchBarBrightnessSnapshot? {
        guard let id = displayID(), let automatic = property("DisplayBrightnessAuto", id: id) as? NSNumber,
              let data = property("DisplayBrightness", id: id) as? [String: Any],
              let level = data["Brightness"] as? NSNumber else { return nil }
        let value = level.doubleValue
        guard value.isFinite, (0...1).contains(value) else { return nil }
        return TouchBarBrightnessSnapshot(automatic: automatic.boolValue, brightness: value)
    }
}
