import CoreAudio

// 기본 입력 장치를 Maono PD300X로 복원
let maonoUID = "AppleUSBAudioEngine:ShenZhen Maono Technology Co., Ltd.:Maono Dynamic Microphone:SERIAL:1,2"

var devProp = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &devProp, 0, nil, &size) == noErr else { exit(1) }
let count = Int(size / 4)
var ids = [AudioObjectID](repeating: 0, count: count)
var cnt = size
guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devProp, 0, nil, &cnt, &ids) == noErr else { exit(1) }

var found: AudioObjectID? = nil
for d in ids {
    var uidProp = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var cf: CFString = "" as CFString
    var sz2 = UInt32(MemoryLayout<CFString>.size)
    if AudioObjectGetPropertyData(d, &uidProp, 0, nil, &sz2, &cf) == noErr, (cf as String) == maonoUID {
        found = d
        break
    }
}

guard let target = found else {
    print("Maono 장치를 못 찾음")
    exit(2)
}

var defaultProp = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var t = target
let st = withUnsafeBytes(of: t) { ptr -> OSStatus in
    guard let base = ptr.baseAddress else { return -1 }
    return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultProp, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), base)
}
print(st == noErr ? "기본 입력 → Maono (id=\(target)) 복원 완료" : "설정 실패: \(st)")
