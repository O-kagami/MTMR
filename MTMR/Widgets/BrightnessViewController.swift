import AppKit
import AVFoundation
import Cocoa
import CoreAudio
import CoreGraphics
import Darwin

class BrightnessViewController: NSCustomTouchBarItem {
    private(set) var sliderItem: CustomSlider!
    private var stepper = BrightnessStepper()
    private var stepTimer: Timer?
    private var refreshTimer: Timer?

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: Double, image: NSImage? = nil) {
        super.init(identifier: identifier)

        if image == nil {
            sliderItem = CustomSlider()
        } else {
            sliderItem = CustomSlider(knob: image!)
        }
        sliderItem.target = self
        sliderItem.action = #selector(BrightnessViewController.sliderValueChanged(_:))
        sliderItem.minValue = 0.0
        sliderItem.maxValue = 100.0
        sliderItem.isContinuous = true
        let initialValue = getBrightness()
        sliderItem.isEnabled = initialValue != nil
        sliderItem.floatValue = (initialValue ?? 0) * 100

        view = sliderItem

        // Timers capture the widget weakly: removing a widget must stop all keys.
        let timer = Timer(timeInterval: max(0.1, refreshInterval), repeats: true) { [weak self] _ in
            self?.updateBrightnessSlider()
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stepTimer?.invalidate()
        refreshTimer?.invalidate()
    }

    private func updateBrightnessSlider() {
        // Do not move the knob underneath an active drag/reconciliation.
        guard !stepper.isActive else { return }
        guard let value = getBrightness() else { sliderItem.isEnabled = false; return }
        sliderItem.isEnabled = true
        sliderItem.floatValue = value * 100
    }

    func cancelAdjustment() {
        _ = stepper.cancel(at: ProcessInfo.processInfo.systemUptime)
        stepTimer?.invalidate()
        stepTimer = nil
    }

    @objc func sliderValueChanged(_ sender: Any) {
        guard let slider = sender as? NSSlider else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard stepper.setTarget(Double(slider.floatValue) / 100, at: now) else {
            updateBrightnessSlider()
            return
        }
        guard stepTimer == nil else { return }
        let timer = Timer(timeInterval: 0.16, repeats: true) { [weak self] _ in
            self?.advanceBrightnessStepper()
        }
        stepTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        advanceBrightnessStepper()
    }

    private func advanceBrightnessStepper() {
        let measured = getBrightness().map(Double.init)
        switch stepper.tick(measured: measured, at: ProcessInfo.processInfo.systemUptime) {
        case .up:
            HIDPostAuxKey(NX_KEYTYPE_BRIGHTNESS_UP)
        case .down:
            HIDPostAuxKey(NX_KEYTYPE_BRIGHTNESS_DOWN)
        case .wait:
            break
        case .stop:
            stepTimer?.invalidate()
            stepTimer = nil
            updateBrightnessSlider()
        }
    }

    // DisplayServices accepts the real built-in display ID, unlike MTMR's
    // original CoreDisplay calls with ID 0 on Apple Silicon.
    private let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private func builtInDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 })
    }

    private func getBrightness() -> Float32? {
        guard let handle = displayServices, let display = builtInDisplay(),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let getter = unsafeBitCast(symbol, to: Getter.self)
        var brightness: Float = 0.5
        guard getter(display, &brightness) == 0, brightness.isFinite, (0...1).contains(brightness) else { return nil }
        return min(1, max(0, brightness))
    }

}
