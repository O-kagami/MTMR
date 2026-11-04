import AppKit
import CoreGraphics
import Darwin

class BrightnessViewController: NSCustomTouchBarItem {
    private(set) var sliderItem: CustomSlider!
    private var refreshTimer: Timer?
    /// The callbacks are delivered on the main thread, after user interaction
    /// or a failed write has been reconciled with the display's actual value.
    var onUserInteraction: (() -> Void)?
    var onUserValue: ((Float?) -> Void)?
    private var lastDragTime: TimeInterval = -.infinity
    private var writeFailed = false
    private let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: Double, image: NSImage? = nil) {
        super.init(identifier: identifier)
        sliderItem = image.map { CustomSlider(knob: $0) } ?? CustomSlider()
        sliderItem.target = self
        sliderItem.action = #selector(sliderValueChanged(_:))
        sliderItem.minValue = 0
        sliderItem.maxValue = 100
        sliderItem.isContinuous = true
        view = sliderItem
        updateBrightnessSlider()
        let timer = Timer(timeInterval: max(0.1, refreshInterval), repeats: true) { [weak self] _ in
            self?.updateBrightnessSlider()
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { refreshTimer?.invalidate() }

    func cancelAdjustment() {
        lastDragTime = -.infinity
        writeFailed = false
        updateBrightnessSlider()
    }

    private func updateBrightnessSlider() {
        guard !writeFailed, ProcessInfo.processInfo.systemUptime - lastDragTime > 0.5 else { return }
        guard let level = getBrightness(), setterAvailable() else { sliderItem.isEnabled = false; return }
        sliderItem.isEnabled = true
        sliderItem.floatValue = level * 100
    }

    @objc func sliderValueChanged(_ sender: Any) {
        guard let slider = sender as? NSSlider else { return }
        lastDragTime = ProcessInfo.processInfo.systemUptime
        onUserInteraction?()
        let requested = slider.floatValue / 100
        guard let handle = displayServices, let display = builtInDisplay(),
              let symbol = dlsym(handle, "DisplayServicesSetBrightness") else {
            slider.isEnabled = false
            lastDragTime = -.infinity
            let actual = getBrightness()
            if let actual = actual { slider.floatValue = actual * 100 }
            onUserValue?(actual.map { $0 * 100 })
            return
        }
        typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let setter = unsafeBitCast(symbol, to: Setter.self)
        let result = BrightnessWriter.apply(requested) { setter(display, $0) }
        if result == .accepted {
            onUserValue?(requested * 100)
        } else {
            writeFailed = true
            slider.isEnabled = false
            let actual = getBrightness()
            if let actual = actual { slider.floatValue = actual * 100 }
            onUserValue?(actual.map { $0 * 100 })
        }
    }

    private func setterAvailable() -> Bool {
        guard let handle = displayServices else { return false }
        return dlsym(handle, "DisplayServicesSetBrightness") != nil
    }
    private func builtInDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { return nil }
        let builtIns = displays.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 }
        guard builtIns.count == 1 else { return nil }
        return builtIns.first
    }
    private func getBrightness() -> Float32? {
        guard let handle = displayServices, let display = builtInDisplay(),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let getter = unsafeBitCast(symbol, to: Getter.self)
        var level: Float = 0
        guard getter(display, &level) == 0, level.isFinite, (0...1).contains(level) else { return nil }
        return level
    }
}
