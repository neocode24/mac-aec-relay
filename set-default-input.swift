import CoreAudio
import Foundation

// 기본 입력 장치를 바꾼다.
//
//   set-default-input              현재 기본 입력을 출력만 한다
//   set-default-input <UID|이름>   해당 장치로 바꾼다 (이름은 일부만 써도 된다)
//
// 시험 중에 기본 장치를 바꿨다가 되돌릴 때 쓴다.

func allDeviceIDs() -> [AudioObjectID] {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                         &prop, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    var cnt = size
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                     &prop, 0, nil, &cnt, &ids) == noErr else { return [] }
    return ids
}

func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var prop = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var cf: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(id, &prop, 0, nil, &size, &cf) == noErr else { return nil }
    return cf as String
}

func deviceUID(_ id: AudioObjectID) -> String? {
    stringProperty(id, kAudioDevicePropertyDeviceUID)
}

func deviceName(_ id: AudioObjectID) -> String? {
    stringProperty(id, kAudioObjectPropertyName)
}

func currentDefaultInput() -> AudioObjectID? {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var id = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                     &prop, 0, nil, &size, &id) == noErr else { return nil }
    return id
}

let args = Array(CommandLine.arguments.dropFirst())

// 인자가 없으면 현재 기본 입력만 알려준다.
guard let hint = args.first, !hint.isEmpty else {
    if let id = currentDefaultInput() {
        print("현재 입력: \(deviceName(id) ?? "?")  uid=\(deviceUID(id) ?? "?")")
    } else {
        print("기본 입력 장치를 못 찾음")
    }
    exit(0)
}

// UID로 먼저 찾고, 없으면 이름에 포함된 문자열로 찾는다.
var target: AudioObjectID? = nil
for id in allDeviceIDs() where deviceUID(id) == hint { target = id; break }
if target == nil {
    let lowered = hint.lowercased()
    for id in allDeviceIDs() {
        if let name = deviceName(id), name.lowercased().contains(lowered) { target = id; break }
    }
}

guard let found = target else {
    print("장치를 못 찾음: \(hint)")
    exit(2)
}

var prop = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var value = found
let status = AudioObjectSetPropertyData(
    AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil,
    UInt32(MemoryLayout<AudioObjectID>.size), &value)

if status == noErr {
    print("기본 입력 → \(deviceName(found) ?? "?")")
} else {
    print("설정 실패: \(status)")
    exit(3)
}
