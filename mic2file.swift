import AVFoundation
import CoreAudio
import AudioUnit
import Foundation

// mic2file — Maono를 HALOutput 입력 전용 유닛으로 녹음해 f32로 저장.
// ffmpeg avfoundation 녹음이 조기 종료하는 문제의 대체재.
// 사용법: mic2file <출력.f32> <초>

var outPath = "/tmp/mic2file.f32"
var seconds = 5.0
let args = Array(CommandLine.arguments.dropFirst())
if args.count > 0 { outPath = args[0] }
if args.count > 1 { seconds = Double(args[1]) ?? 5.0 }

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

FileManager.default.createFile(atPath: outPath, contents: nil)
guard let fh = FileHandle(forWritingAtPath: outPath) else { print("file open fail"); exit(1) }

var desc = AudioComponentDescription(
    componentType: kAudioUnitType_Output,
    componentSubType: kAudioUnitSubType_HALOutput,
    componentManufacturer: kAudioUnitManufacturer_Apple,
    componentFlags: 0, componentFlagsMask: 0)
guard let comp = AudioComponentFindNext(nil, &desc) else { print("no comp"); exit(1) }
var u: AudioUnit?
guard AudioComponentInstanceNew(comp, &u) == noErr, let unit = u else { print("instance fail"); exit(1) }

var dev = micID
guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, 4) == noErr else { print("device fail"); exit(1) }
var en: UInt32 = 1
guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &en, 4) == noErr else { print("enable fail"); exit(1) }
var dis: UInt32 = 0
AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &dis, 4)

var fmt = AudioStreamBasicDescription(
    mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
    mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
    mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fmt, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

var gUnit: AudioUnit? = nil
var gFH: FileHandle? = nil
var total = 0
let inputProc: AURenderCallback = { _, ioActionFlags, inTimeStamp, _, inNumberFrames, _ in
    guard let un = gUnit else { return noErr }
    let frames = Int(inNumberFrames)
    guard frames > 0, frames <= 8192 else { return noErr }
    var buffer = [Float32](repeating: 0, count: frames)
    buffer.withUnsafeMutableBufferPointer { bp in
        var abl = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: bp.baseAddress))
        let st = AudioUnitRender(un, ioActionFlags, inTimeStamp, 1, inNumberFrames, &abl)
        if st == noErr {
            total += frames
            if let fh = gFH {
                let data = Data(bytes: bp.baseAddress!, count: frames * 4)
                _ = try? fh.write(contentsOf: data)
            }
        }
    }
    return noErr
}
var cbv = AURenderCallbackStruct(inputProc: inputProc, inputProcRefCon: nil)
guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &cbv, UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr else { print("cb fail"); exit(1) }

guard AudioUnitInitialize(unit) == noErr else { print("init fail"); exit(1) }
gUnit = unit
gFH = fh
guard AudioOutputUnitStart(unit) == noErr else { print("start fail"); exit(1) }

print("recording \(seconds)s → \(outPath)")
Thread.sleep(forTimeInterval: seconds)
AudioOutputUnitStop(unit)
try? fh.close()
print("frames=\(total) (\(Double(total)/48000.0)s)")
