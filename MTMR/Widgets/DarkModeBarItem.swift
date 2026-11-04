import Foundation

class DarkModeBarItem: CustomButtonTouchBarItem, Widget {
    static var name: String = "darkmode"
    static var identifier: String = "com.toxblh.mtmr.darkmode"

    private var timer: Timer!
    private lazy var darkOn = makeInlineScriptAction("tell application \"System Events\" to tell appearance preferences to set dark mode to true")
    private lazy var darkOff = makeInlineScriptAction("tell application \"System Events\" to tell appearance preferences to set dark mode to false")

    init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier, title: "")
        isBordered = false
        setWidth(value: 24)

        actions.append(ItemAction(trigger: .singleTap) { [weak self] in self?.DarkModeToggle() })

        timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)

        refresh()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func DarkModeToggle() {
        if DarkMode.isEnabled { darkOff() } else { darkOn() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
    }

    @objc func refresh() {
        image = DarkMode.isEnabled ? #imageLiteral(resourceName: "dark-mode-on") : #imageLiteral(resourceName: "dark-mode-off")
    }
}


struct DarkMode {
    static var isEnabled: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}
