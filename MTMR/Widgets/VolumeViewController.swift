import AppKit
import AVFoundation
import Cocoa
import CoreAudio

class VolumeViewController: NSCustomTouchBarItem {
    private(set) var sliderItem: CustomSlider!
    private var currentDeviceId: AudioObjectID = AudioObjectID(0)
    private var lastUserChange: TimeInterval = -.infinity
    private var pendingHardwareSync: DispatchWorkItem?
    var onHardwareValue: ((Float?) -> Void)?

    init(identifier: NSTouchBarItem.Identifier, image: NSImage? = nil) {
        super.init(identifier: identifier)

        if image == nil {
            sliderItem = CustomSlider()
        } else {
            sliderItem = CustomSlider(knob: image!)
        }
        sliderItem.target = self
        sliderItem.action = #selector(VolumeViewController.sliderValueChanged(_:))
        sliderItem.minValue = 0.0
        sliderItem.maxValue = 100.0
        sliderItem.floatValue = getInputGain() * 100

        view = sliderItem
        
        currentDeviceId = defaultDeviceID
        self.addAudioRouteChangedListener()
        self.addCurrentAudioVolumeChangedListener()
    }
    
    private func addAudioRouteChangedListener() {
        let audioId = AudioObjectID(bitPattern: kAudioObjectSystemObject)
        var forPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster)
        AudioObjectAddPropertyListenerBlock(audioId, &forPropertyAddress, nil, audioRouteChanged)
    }
    

    func audioRouteChanged(numberAddresses _: UInt32, addresses _: UnsafePointer<AudioObjectPropertyAddress>) {
        self.removeLastAudioVolumeChangeListener()
        currentDeviceId = defaultDeviceID
        self.addCurrentAudioVolumeChangedListener()
        DispatchQueue.main.async { [weak self] in self?.scheduleHardwareSync() }
    }
    
    private func addCurrentAudioVolumeChangedListener() {
        var forPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMaster
        )

        AudioObjectAddPropertyListenerBlock(defaultDeviceID, &forPropertyAddress, nil, audioObjectPropertyListenerBlock)
    }
    
    private func removeLastAudioVolumeChangeListener() {
        var forPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMaster
        )

        AudioObjectRemovePropertyListenerBlock(currentDeviceId, &forPropertyAddress, nil, audioObjectPropertyListenerBlock)
    }

    func audioObjectPropertyListenerBlock(numberAddresses _: UInt32, addresses _: UnsafePointer<AudioObjectPropertyAddress>) {
        DispatchQueue.main.async { [weak self] in self?.scheduleHardwareSync() }
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pendingHardwareSync?.cancel()
        sliderItem.unbind(NSBindingName.value)
    }

    // Delay hardware callbacks while a user is dragging; replay the latest
    // actual value once input has settled instead of moving the thumb backwards.
    private func scheduleHardwareSync() {
        pendingHardwareSync?.cancel()
        let elapsed = ProcessInfo.processInfo.systemUptime - lastUserChange
        let delay = max(0, 0.6 - elapsed)
        let task = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let actual = self.readOutputGain().map { $0 * 100 }
            if let actual = actual { self.sliderItem.floatValue = actual }
            self.onHardwareValue?(actual)
        }
        pendingHardwareSync = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    @discardableResult func applySliderValue(_ slider: NSSlider) -> Float? {
        lastUserChange = ProcessInfo.processInfo.systemUptime
        pendingHardwareSync?.cancel()
        let requested = slider.floatValue.rounded()
        let outcome = LevelWritePolicy.apply(requested, write: { [weak self] percent in
            guard let self = self else { return false }
            return self.setInputGain(percent / 100) == noErr
        }, readActual: { [weak self] in
            self?.readOutputGain().map { $0 * 100 }
        })
        switch outcome {
        case .accepted(let level):
            scheduleHardwareSync()
            return level
        case .reverted(let actual):
            slider.floatValue = actual
            return actual
        case .unavailable:
            slider.isEnabled = false
            return nil
        }
    }
    @objc func sliderValueChanged(_ sender: Any) {
        if let slider = sender as? NSSlider { _ = applySliderValue(slider) }
    }

    private var defaultDeviceID: AudioObjectID {
        var deviceID: AudioObjectID = AudioObjectID(0)
        var size: UInt32 = UInt32(MemoryLayout<AudioObjectID>.size)
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mSelector = AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice)
        address.mScope = AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMaster)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func getInputGain() -> Float32 { readOutputGain() ?? 0.5 }

    private func readOutputGain() -> Float32? {
        var volume: Float32 = 0.5
        var size: UInt32 = UInt32(MemoryLayout.size(ofValue: volume))
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mSelector = AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMaster)
        let result = AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &volume)
        guard result == noErr, volume.isFinite, (0...1).contains(volume) else { return nil }
        return volume
    }

    private func setInputGain(_ volume: Float32) -> OSStatus {
        var inputVolume: Float32 = volume

        if inputVolume == 0.0 {
            _ = setMute(mute: 1)
        } else {
            _ = setMute(mute: 0)
        }

        let size: UInt32 = UInt32(MemoryLayout.size(ofValue: inputVolume))
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMaster)
        address.mSelector = AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        return AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &inputVolume)
    }

    private func setMute(mute: Int) -> OSStatus {
        var muteVal: Int = mute
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mSelector = AudioObjectPropertySelector(kAudioDevicePropertyMute)
        let size: UInt32 = UInt32(MemoryLayout.size(ofValue: muteVal))
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMaster)
        return AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &muteVal)
    }
}
