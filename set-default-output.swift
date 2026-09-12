import CoreAudio
import Foundation

// 기본 출력 장치를 UID로 지정하거나, 현재 값을 출력한다.
// 사용법: set-default-output            (현재 출력 표시)
//         set-default-output <UID>      (해당 장치로 변경)

func allDevices() -> [AudioObjectID] {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    var cnt = size
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &cnt, &ids) == noErr else { return [] }
    return ids
}

func stringProp(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
    var prop = AudioObjectPropertyAddress(mSelector: sel,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var s: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(id, &prop, 0, nil, &size, &s) == noErr else { return nil }
    return s as String
}

func currentOutput() -> AudioObjectID {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var dev: AudioObjectID = 0
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size, &dev)
    return dev
}

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty {
    let cur = currentOutput()
    print("현재 출력: \(stringProp(cur, kAudioObjectPropertyName) ?? "?")  uid=\(stringProp(cur, kAudioDevicePropertyDeviceUID) ?? "?")")
    exit(0)
}

let targetUID = args[0]
guard let dev = allDevices().first(where: { stringProp($0, kAudioDevicePropertyDeviceUID) == targetUID }) else {
    print("UID를 찾을 수 없음: \(targetUID)")
    exit(1)
}

var prop = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var d = dev
let st = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil,
                                    UInt32(MemoryLayout<AudioObjectID>.size), &d)
if st == noErr {
    print("출력 변경됨 -> \(stringProp(dev, kAudioObjectPropertyName) ?? "?")")
} else {
    print("변경 실패 status=\(st)")
    exit(2)
}
