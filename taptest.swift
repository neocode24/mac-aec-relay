import CoreAudio
import AVFoundation
import Foundation

// macOS 14.2+ Core Audio process tap 으로 다른 프로세스의 출력 신호를
// 잡을 수 있는지 확인한다. 되면 AEC 참조 신호에 BlackHole 이 필요 없다.
//
// 사용법: taptest <PID>      (그 프로세스의 출력을 tap)
//         taptest            (시스템 전체 출력을 tap)

setvbuf(stdout, nil, _IOLBF, 0)

func die(_ m: String) -> Never {
    FileHandle.standardError.write(("FATAL: " + m + "\n").data(using: .utf8)!)
    exit(1)
}

// ---- 대상 프로세스의 AudioObjectID 찾기 ----
func processObjectID(pid: pid_t) -> AudioObjectID? {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var p = pid
    var obj: AudioObjectID = 0
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                        UInt32(MemoryLayout<pid_t>.size), &p, &size, &obj)
    return st == noErr && obj != 0 ? obj : nil
}

let args = Array(CommandLine.arguments.dropFirst())

// ---- tap 서술자 만들기 ----
let desc: CATapDescription
if let first = args.first, let pid = pid_t(first) {
    guard let obj = processObjectID(pid: pid) else { die("PID \(pid) 의 오디오 객체를 못 찾음 (그 프로세스가 소리를 내고 있어야 한다)") }
    desc = CATapDescription(stereoMixdownOfProcesses: [obj])
    print("대상: PID \(pid) (audio object \(obj))")
} else {
    desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    print("대상: 시스템 전체 출력")
}
desc.name = "aec-ref-tap-test"
desc.isPrivate = true
desc.muteBehavior = .unmuted   // 원래 스피커로도 계속 나가게 둔다

var tapID: AudioObjectID = 0
let stTap = AudioHardwareCreateProcessTap(desc, &tapID)
guard stTap == noErr, tapID != 0 else { die("AudioHardwareCreateProcessTap 실패 status=\(stTap)") }
print("tap 생성됨 id=\(tapID) uid=\(desc.uuid.uuidString)")

defer { AudioHardwareDestroyProcessTap(tapID) }

// ---- tap 을 품은 private aggregate 만들기 ----
let aggUID = "aec-ref-tap-agg"
let aggDesc: [String: Any] = [
    kAudioAggregateDeviceNameKey as String: "aec-ref-tap-agg",
    kAudioAggregateDeviceUIDKey as String: aggUID,
    kAudioAggregateDeviceIsPrivateKey as String: 1,
    kAudioAggregateDeviceIsStackedKey as String: 0,
    kAudioAggregateDeviceTapAutoStartKey as String: 1,
    kAudioAggregateDeviceSubDeviceListKey as String: [],
    kAudioAggregateDeviceTapListKey as String: [
        [ kAudioSubTapUIDKey as String: desc.uuid.uuidString,
          kAudioSubTapDriftCompensationKey as String: 1 ]
    ],
]
var aggID: AudioDeviceID = 0
let stAgg = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
guard stAgg == noErr, aggID != 0 else { die("aggregate 생성 실패 status=\(stAgg)") }
print("aggregate 생성됨 id=\(aggID)")

defer { AudioHardwareDestroyAggregateDevice(aggID) }

// ---- 레벨 측정 ----
final class Meter { 
    var peak: Float = 0
    var frames = 0
    let lock = NSLock()
}
let meter = Meter()

var ioProcID: AudioDeviceIOProcID?
let stProc = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggID, nil) { _, inData, _, _, _ in
    let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    for buf in list {
        guard let d = buf.mData else { continue }
        let n = Int(buf.mDataByteSize) / MemoryLayout<Float32>.size
        let p = d.assumingMemoryBound(to: Float32.self)
        var localPeak: Float = 0
        for i in 0..<n {
            let a = abs(p[i])
            if a > localPeak { localPeak = a }
        }
        meter.lock.lock()
        if localPeak > meter.peak { meter.peak = localPeak }
        meter.frames += n
        meter.lock.unlock()
    }
}
guard stProc == noErr, let procID = ioProcID else { die("IOProc 생성 실패 status=\(stProc)") }

guard AudioDeviceStart(aggID, procID) == noErr else { die("AudioDeviceStart 실패") }
print("측정 시작 (6초)...")

// Stop/Destroy 가 걸리는 사례가 있어 매초 중간 결과를 찍는다.
for s in 1...6 {
    Thread.sleep(forTimeInterval: 1.0)
    meter.lock.lock()
    let p = meter.peak
    let f = meter.frames
    meter.lock.unlock()
    let d = p > 0 ? 20 * log10(Double(p)) : -999
    print(String(format: "  [%ds] frames=%d peak=%.1f dB", s, f, d))
}

meter.lock.lock()
let peak = meter.peak
let frames = meter.frames
meter.lock.unlock()

let db = peak > 0 ? 20 * log10(Double(peak)) : -999
print(String(format: "RESULT frames=%d peak=%.1f dB", frames, db))
if frames == 0 {
    print("=> 콜백이 0회. tap 에서 데이터가 안 온다.")
} else if db < -100 {
    print("=> 데이터는 오지만 무음. 대상이 소리를 내고 있었나?")
} else {
    print("=> tap 성공. 참조 신호를 BlackHole 없이 얻을 수 있다.")
}
print("정리 중...")
AudioDeviceStop(aggID, procID)
AudioDeviceDestroyIOProcID(aggID, procID)
print("완료")
