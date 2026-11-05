import Foundation
import CoreAudio

func probe(defaultStatus: OSStatus = noErr, device: AudioObjectID = 42,
           has: Bool = true, setStatus: OSStatus = noErr, settable: Bool = true,
           readStatus: OSStatus = noErr, level: Float32 = 0.6) -> (OutputVolumeReading, [String]) {
    var calls: [String] = []
    let result = OutputVolumeProbe.evaluate(defaultDevice: { calls.append("default"); return (defaultStatus, device) },
        hasProperty: { id in precondition(id == device); calls.append("has"); return has },
        isSettable: { id in precondition(id == device); calls.append("settable"); return (setStatus, settable) },
        read: { id in precondition(id == device); calls.append("read"); return (readStatus, level) })
    return (result, calls)
}
let good = probe()
precondition(good.0.device == 42 && good.0.capability == .available(0.6))
precondition(good.1 == ["default", "has", "settable", "read"])
let defaultFailure = probe(defaultStatus: -1)
precondition(defaultFailure.0.capability == .unknown && defaultFailure.1 == ["default"])
let noDevice = probe(device: AudioObjectID(kAudioObjectUnknown))
precondition(noDevice.0.capability == .unavailable && noDevice.1 == ["default"])
let noProperty = probe(has: false)
precondition(noProperty.0.capability == .unavailable && noProperty.1 == ["default", "has"])
let setError = probe(setStatus: -2)
precondition(setError.0.capability == .unknown && setError.1 == ["default", "has", "settable"])
let notSettable = probe(settable: false)
precondition(notSettable.0.capability == .unavailable && notSettable.1 == ["default", "has", "settable"])
precondition(probe(readStatus: -3).0.capability == .unknown)
precondition(probe(level: .nan).0.capability == .unknown)
precondition(probe(level: -0.01).0.capability == .unknown)
precondition(probe(level: 1.01).0.capability == .unknown)
precondition(probe(level: 0).0.capability == .available(0))
precondition(probe(level: 1).0.capability == .available(1))
print("AudioOutputProbe tests passed")
