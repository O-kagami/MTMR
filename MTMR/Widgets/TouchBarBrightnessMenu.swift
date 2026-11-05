import AppKit

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
    func makeItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Touch Barの明るさ", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Touch Barの明るさ")
        menu.autoenablesItems = false; menu.delegate = self
        let info = NSMenuItem(title: "取得中…", action: nil, keyEquivalent: "")
        info.isEnabled = false; menu.addItem(info); status = info
        let system = NSMenuItem(title: "システムに任せる（即時復帰しない場合あり）", action: #selector(selectSystem(_:)), keyEquivalent: "")
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
                self.status?.title = self.requestedTemporary ? "一時設定（OSで変わる場合あり）" : "システムに任せています"
            case .indeterminate:
                self.blocked = true; self.available = false; self.status?.title = "応答がなく、結果を確認できません"
            default:
                self.available = false; self.status?.title = "利用できません"
            }
            self.updateControls()
        }
    }
    @objc private func selectSystem(_ sender: Any?) {
        guard !pending, !blocked else { return }
        requestedTemporary = false
        // No write, no setting of Auto: macOS may replace the previous transient
        // value on its own schedule, not necessarily immediately.
        status?.title = "システムに任せています（即時復帰しない場合あり）"
        updateControls()
    }
    @objc private func changeBrightness(_ sender: NSSlider) {
        let value = sender.doubleValue
        guard !pending, !blocked, available, value.isFinite, (5...100).contains(value) else { return }
        pending = true; status?.title = "設定中…"; updateControls()
        client.request(["set", String(value), String(getpid())]) { [weak self] result in
            guard let self = self else { return }
            self.pending = false
            switch result {
            case .success:
                self.requestedTemporary = true
                self.status?.title = "一時設定（OSで変わる場合あり）"
                self.refresh() // show the reported actual value, not the request
                return
            case .indeterminate:
                self.blocked = true; self.available = false
                self.status?.title = "応答がなく、結果を確認できません"
            default:
                self.available = false; self.status?.title = "設定できません"
            }
            self.updateControls()
        }
    }
    func stop() { client.stop() }
}
