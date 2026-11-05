import Foundation
import CoreAudio
import AudioToolbox

/// The same virtual-main output property used by the volume slider.
enum OutputVolumeCapability: Equatable {
    case available(Float32)
    case unavailable
    case unknown
}

struct OutputVolumeReading {
    let device: AudioObjectID?
    let capability: OutputVolumeCapability
}

enum OutputVolumeProbe {
    /// Injectable queries keep error and device capability handling testable
    /// without changing sound hardware.
    static func evaluate(
        defaultDevice: () -> (OSStatus, AudioObjectID),
        hasProperty: (AudioObjectID) -> Bool,
        isSettable: (AudioObjectID) -> (OSStatus, Bool),
        read: (AudioObjectID) -> (OSStatus, Float32)
    ) -> OutputVolumeReading {
        let (deviceStatus, device) = defaultDevice()
        guard deviceStatus == noErr else { return .init(device: nil, capability: .unknown) }
        guard device != AudioObjectID(kAudioObjectUnknown) else { return .init(device: nil, capability: .unavailable) }
        guard hasProperty(device) else { return .init(device: device, capability: .unavailable) }
        let (settableStatus, settable) = isSettable(device)
        guard settableStatus == noErr else { return .init(device: device, capability: .unknown) }
        guard settable else { return .init(device: device, capability: .unavailable) }
        let (readStatus, level) = read(device)
        guard readStatus == noErr, level.isFinite, (0...1).contains(level) else { return .init(device: device, capability: .unknown) }
        return .init(device: device, capability: .available(level))
    }

    static func currentDevice() -> (OSStatus, AudioObjectID) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMaster)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return (status, device)
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMaster)
    }

    static func current() -> OutputVolumeReading {
        evaluate(defaultDevice: currentDevice, hasProperty: { device in
            var address = volumeAddress()
            return AudioObjectHasProperty(device, &address)
        }, isSettable: { device in
            var address = volumeAddress()
            var settable: DarwinBoolean = false
            let status = AudioObjectIsPropertySettable(device, &address, &settable)
            return (status, settable.boolValue)
        }, read: { device in
            var address = volumeAddress()
            var level: Float32 = -1
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level)
            return (status, level)
        })
    }
}
