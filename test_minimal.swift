import AVFoundation
import CoreAudio
import AudioUnit
import Foundation

// 최소 재현: HALOutput 입력 전용 유닛의 입력 콜백이 불리는가?
var cbCount = 0
var lastFrames = 0

let micUID = "AppleUSBAudioEngine:ShenZhen Maono Technology Co., Ltd.:Maono Dynamic Microphone:SERIAL:1,2"

func uidToID(_ uid: String) -> AudioObjectID? {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size) == noErr, size > 0 else { return nil }
    let count = Int(size / UInt32(MemoryLayout<AudioObjectID>.size))
    var ids = [AudioObjectID](repeating: 0, count: count)
    var cnt = size
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &cnt, &ids) == noErr else { return nil }
    for id in ids {
        var uidProp = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cf: CFString = "" as CFString
        var sz = UInt32(MemoryLayout<CFString>.size)
        if AudioObjectGetPropertyData(id, &uidProp, 0, nil, &sz, &cf) == noErr, (cf as String) == uid { return id }
    }
    return nil
}

guard let micID = uidToID(micUID) else { print("no mic"); exit(1) }
print("mic id=\(micID)")

var desc = AudioComponentDescription(
    componentType: kAudioUnitType_Output,
    componentSubType: kAudioUnitSubType_HALOutput,
    componentManufacturer: kAudioUnitManufacturer_Apple,
    componentFlags: 0, componentFlagsMask: 0)
guard let comp = AudioComponentFindNext(nil, &desc) else { print("no comp"); exit(1) }
var u: AudioUnit?
guard AudioComponentInstanceNew(comp, &u) == noErr, let unit = u else { print("instance fail"); exit(1) }

var dev = micID
print("CurrentDevice: \(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, 4))")

var en: UInt32 = 1
print("EnableIO(in): \(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &en, 4))")
var dis: UInt32 = 0
print("EnableIO(out)=0: \(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &dis, 4))")

var fmt = AudioStreamBasicDescription(
    mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
    mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
    mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
print("StreamFormat: \(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fmt, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))")

// 콜백 카운트를 올리는 input callback
var cb = AURenderCallbackStruct(
    inputProc: { _, _, _, _, inNumberFrames, ioData in
        cbCount += 1
        lastFrames = Int(inNumberFrames)
        return noErr
    },
    inputProcRefCon: nil)
print("SetInputCallback: \(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))")

print("Initialize: \(AudioUnitInitialize(unit))")
print("Start: \(AudioOutputUnitStart(unit))")

for sec in 1...5 {
    Thread.sleep(forTimeInterval: 1.0)
    print("t=\(sec)s callbacks=\(cbCount) lastFrames=\(lastFrames)")
}
AudioOutputUnitStop(unit)
print("DONE cb=\(cbCount)")
