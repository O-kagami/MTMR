import AppKit
import CoreGraphics
import Darwin

/// Read on a background serial queue so an unavailable private display API
/// cannot block the menu or cause an accumulation of pending reads.
private final class BuiltInDisplayBrightnessReader {
    private let library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    func read() -> Double? {
        guard let library = library, let symbol = dlsym(library, "DisplayServicesGetBrightness") else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { return nil }
        let builtIns = displays.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 }
        guard builtIns.count == 1, let display = builtIns.first else { return nil }
        typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        var value: Float = 0
        guard unsafeBitCast(symbol, to: Getter.self)(display, &value) == 0,
              value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }
}

/// Menu uses an isolated one-request helper. Slider changes are sent only on
/// release; system mode never changes a macOS automatic-brightness preference.
final class TouchBarBrightnessMenu: NSObject, NSMenuDelegate {
    private let client: TouchBarRequesting
    private var status: NSMenuItem?
    private var systemMode: NSMenuItem?
    private var slider: NSSlider?
    private var label: NSTextField?
    private var available = false
    private var pending = false
    private var blocked = false
    private var requestedTemporary = false
    private let displayReader = BuiltInDisplayBrightnessReader()
    private let displayQueue = DispatchQueue(label: "mtmr.display.brightness.read", qos: .utility)
    private var displayTimer: Timer?
    private var displayReadPending = false
    private var displayGeneration: UInt64 = 0
    private var lastDisplayBrightness: Double?
    private var queuedSync: Double?
    private var stopped = false

    override init() {
        let url = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("TouchBarBrightnessHelper")
            ?? URL(fileURLWithPath: "/nonexistent/TouchBarBrightnessHelper")
        client = IsolatedTouchBarClient(helper: url)
        super.init()
    }
    init(client: TouchBarRequesting) {
        self.client = client
        super.init()
    }

    func startMonitoringDisplay() {
        guard displayTimer == nil, !stopped else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.readDisplay() }
        displayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        readDisplay()
    }

    private func readDisplay() {
        guard !blocked, !stopped else { return }
        flushSync()
        guard !displayReadPending else { return }
        displayReadPending = true
        let generation = displayGeneration
        displayQueue.async { [weak self] in
            guard let self = self else { return }
            let value = self.displayReader.read()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.stopped else { return }
                self.displayReadPending = false
                guard generation == self.displayGeneration else { self.readDisplay(); return }
                if let value = value { self.observeDisplayBrightness(value) }
            }
        }
    }

    /// The first successful observation establishes a baseline only. A manual
    /// Touch Bar adjustment remains in effect until the display actually changes.
    func observeDisplayBrightness(_ value: Double) {
        guard !stopped, !blocked, value.isFinite, (0...1).contains(value) else { return }
        guard let previous = lastDisplayBrightness else { lastDisplayBrightness = value; return }
        guard abs(value - previous) >= 0.005 else { return }
        lastDisplayBrightness = value
        queuedSync = max(5, min(100, value * 100))
        flushSync()
    }

    private func flushSync() {
        guard !pending, !blocked, !stopped, let value = queuedSync else { return }
        queuedSync = nil
        pending = true
        updateControls()
        client.request(["set", String(value), String(getpid())]) { [weak self] result in
            guard let self = self, !self.stopped else { return }
            self.pending = false
            switch result {
            case .success:
                self.requestedTemporary = false
                self.status?.title = "ディスプレイの明るさに連動"
            case .indeterminate:
                self.blocked = true; self.available = false; self.queuedSync = nil
                self.status?.title = "応答がなく、結果を確認できません"
            case .busy:
                self.queuedSync = value
            default:
                self.status?.title = "Touch Barの明るさを設定できません"
            }
            self.updateControls()
            // A busy result cannot be retried immediately in a tight loop.
            if case .busy = result { return }
            self.flushSync()
        }
    }
    func makeItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Touch Barの明るさ", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Touch Barの明るさ")
        menu.autoenablesItems = false; menu.delegate = self
        let info = NSMenuItem(title: "取得中…", action: nil, keyEquivalent: "")
        info.isEnabled = false; menu.addItem(info); status = info
        let system = NSMenuItem(title: "ディスプレイの明るさに連動", action: #selector(selectSystem(_:)), keyEquivalent: "")
        system.target = self; menu.addItem(system); systemMode = system
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 38))
        let control = NSSlider(value: 50, minValue: 5, maxValue: 100, target: self, action: #selector(changeBrightness(_:)))
        control.frame = NSRect(x: 12, y: 6, width: 165, height: 26)
        control.isContinuous = false; control.isEnabled = false; view.addSubview(control); slider = control
        let value = NSTextField(labelWithString: "--")
        value.alignment = .right; value.frame = NSRect(x: 181, y: 9, width: 45, height: 20)
        view.addSubview(value); label = value
        let row = NSMenuItem(); row.view = view; menu.addItem(row)
        root.submenu = menu
        updateControls()
        return root
    }
    func menuWillOpen(_ menu: NSMenu) { refresh() }
    private func updateControls() {
        slider?.isEnabled = available && !pending && !blocked
        systemMode?.isEnabled = !pending && !blocked
        systemMode?.state = requestedTemporary ? .off : .on
    }
    private func refresh() {
        guard !pending, !blocked else { return }
        pending = true; status?.title = "取得中…"; updateControls()
        client.request(["read", String(getpid())]) { [weak self] result in
            guard let self = self else { return }
            self.pending = false
            switch result {
            case let .success(data):
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let level = json["brightness"] as? NSNumber, level.doubleValue.isFinite,
                      (0...1).contains(level.doubleValue) else {
                    self.available = false; self.status?.title = "利用できません"; break
                }
                self.available = true
                self.slider?.doubleValue = max(5, min(100, level.doubleValue * 100))
                self.label?.stringValue = "\(Int((level.doubleValue * 100).rounded()))%"
                self.status?.title = self.requestedTemporary ? "手動設定中（画面の明るさ変更で連動）" : "ディスプレイの明るさに連動"
            case .indeterminate:
                self.blocked = true; self.available = false; self.status?.title = "応答がなく、結果を確認できません"
            default:
                self.available = false; self.status?.title = "利用できません"
            }
            self.updateControls()
            self.flushSync()
        }
    }
    @objc private func selectSystem(_ sender: Any?) {
        guard !pending, !blocked else { return }
        requestedTemporary = false
        // No write, no setting of Auto: macOS may replace the previous transient
        // value on its own schedule, not necessarily immediately.
        status?.title = "次の画面の明るさ変更から連動します"
        updateControls()
    }
    @objc private func changeBrightness(_ sender: NSSlider) {
        let value = sender.doubleValue
        guard !pending, !blocked, available, value.isFinite, (5...100).contains(value) else { return }
        queuedSync = nil
        // A read started before this action must not overwrite the chosen level.
        displayGeneration &+= 1
        lastDisplayBrightness = nil
        if displayTimer != nil { readDisplay() }
        pending = true; status?.title = "設定中…"; updateControls()
        client.request(["set", String(value), String(getpid())]) { [weak self] result in
            guard let self = self else { return }
            self.pending = false
            switch result {
            case .success:
                self.requestedTemporary = true
                self.status?.title = "手動設定中（画面の明るさ変更で連動）"
                self.refresh() // show the reported actual value, not the request
                return
            case .indeterminate:
                self.blocked = true; self.available = false
                self.status?.title = "応答がなく、結果を確認できません"
            default:
                self.available = false; self.status?.title = "設定できません"
            }
            self.updateControls()
            self.flushSync()
        }
    }
    func stop() { stopped = true; displayTimer?.invalidate(); displayTimer = nil; queuedSync = nil; client.stop() }
}
