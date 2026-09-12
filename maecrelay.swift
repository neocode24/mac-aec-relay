import AVFoundation
import CoreAudio
import AudioUnit
import Foundation
import Darwin

// ============================================================
// maecrelay — macOS 통화 에코 제거 AEC 중계
//
// 모드:
//   raw : VPIO 없이 Maono → BH2 통과 (측정 체인 검증/비교 기준)
//   a   : VPIO, CurrentDevice 미지정(기본 입출력 = Maono/DELL),
//         출력 버스 활성 + 무음 렌더. VPIO가 시스템 출력(하드웨어
//         믹스)을 AEC 참조로 쓰는지 시험한다.
//   ai  : VPIO 입력 전용(출력 버스 비활성). 참조 없이 AEC가
//         동작하는지 시험한다.
//   b   : private aggregate(Maono+DELL)에 VPIO 바인딩.
//         --farfile 의 원격 음성을 BH16에 쓰고(IOProc 출력),
//         BH16 루프백 입력을 VPIO 출력 버스로 렌더해 DELL에서
//         재생 = AEC 참조 확보. 처리된 마이크는 BH2로.
//
// 공통: BH2는 IOProc으로 직접 write. 모든 측정 미터는 주기 출력.
// ============================================================

setvbuf(stdout, nil, _IOLBF, 0)

var gRunning = true
signal(SIGINT) { _ in gRunning = false }
signal(SIGTERM) { _ in gRunning = false }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(("FATAL: " + msg + "\n").data(using: .utf8)!)
    exit(1)
}

func must(_ status: OSStatus, _ what: String) {
    if status != noErr {
        FileHandle.standardError.write(("ERROR \(what): \(status)\n").data(using: .utf8)!)
        exit(2)
    }
}

// ---------- CoreAudio helpers ----------

func allDeviceIDs() -> [AudioObjectID] {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size) == noErr, size > 0 else { return [] }
    let count = Int(size / UInt32(MemoryLayout<AudioObjectID>.size))
    var ids = [AudioObjectID](repeating: 0, count: count)
    var cnt = size
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &cnt, &ids) == noErr else { return [] }
    return ids
}

func deviceUID(_ id: AudioObjectID) -> String? {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var cfname: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(id, &prop, 0, nil, &size, &cfname) == noErr else { return nil }
    return cfname as String
}

func deviceName(_ id: AudioObjectID) -> String? {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var cfname: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(id, &prop, 0, nil, &size, &cfname) == noErr else { return nil }
    return cfname as String
}

func uidToID(_ uid: String) -> AudioObjectID? {
    for id in allDeviceIDs() {
        if deviceUID(id) == uid { return id }
    }
    return nil
}

func nominalRate(_ id: AudioObjectID) -> Float64 {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var r: Float64 = 0
    var size = UInt32(MemoryLayout<Float64>.size)
    guard AudioObjectGetPropertyData(id, &prop, 0, nil, &size, &r) == noErr else { return 0 }
    return r
}

func setNominalRate(_ id: AudioObjectID, _ rate: Float64) -> OSStatus {
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var r = rate
    return AudioObjectSetPropertyData(id, &prop, 0, nil, UInt32(MemoryLayout<Float64>.size), &r)
}

// ---------- level metering ----------

final class Meter {
    private var peak: Double = 0
    private var sumSquares: Double = 0
    private var frameCount: Int = 0
    private var callbackCount: Int = 0
    private let lock = NSLock()
    private var totalPeak: Double = 0
    private var totalRms: Double = 0
    private var totalFrames: Int = 0
    private var totalCallbacks: Int = 0

    func process(_ samples: [Float32]) {
        var p = 0.0
        var ss = 0.0
        for s in samples {
            let d = Double(s)
            let a = abs(d)
            if a > p { p = a }
            ss += d * d
        }
        lock.lock()
        if p > peak { peak = p }
        sumSquares += ss
        frameCount += samples.count
        callbackCount += 1
        lock.unlock()
    }

    func drain() -> (peakDb: Double, rmsDb: Double, callbacks: Int) {
        lock.lock()
        let p = peak, f = frameCount, ss = sumSquares, cb = callbackCount
        if p > totalPeak { totalPeak = p }
        totalRms += ss
        totalFrames += f
        totalCallbacks += cb
        peak = 0; sumSquares = 0; frameCount = 0; callbackCount = 0
        lock.unlock()
        if cb == 0 { return (-999, -999, 0) }
        let peakDb = p > 0 ? 20 * log10(p) : -999
        let rmsDb = f > 0 ? 10 * log10(max(ss / Double(f), 1e-12)) : -999
        return (peakDb, rmsDb, cb)
    }

    func overall() -> (peakDb: Double, rmsDb: Double, callbacks: Int) {
        lock.lock()
        defer { lock.unlock() }
        let peakDb = totalPeak > 0 ? 20 * log10(totalPeak) : -999
        let rmsDb = totalFrames > 0 ? 10 * log10(max(totalRms / Double(totalFrames), 1e-12)) : -999
        return (peakDb, rmsDb, totalCallbacks)
    }
}

// ---------- ring buffer ----------

final class Ring {
    private var storage: [Float32]
    private let mask: Int
    private var rIdx = 0
    private var wIdx = 0
    private let lock = NSLock()

    init(capacityPow2: Int) {
        storage = [Float32](repeating: 0, count: capacityPow2)
        mask = capacityPow2 - 1
    }

    func write(_ s: [Float32]) {
        lock.lock()
        for v in s {
            storage[wIdx & mask] = v
            wIdx += 1
        }
        if wIdx - rIdx > storage.count { rIdx = wIdx - storage.count }
        lock.unlock()
    }

    func read(_ n: Int) -> [Float32] {
        var out = [Float32](repeating: 0, count: n)
        lock.lock()
        let avail = wIdx - rIdx
        let m = min(n, avail)
        if m > 0 {
            for i in 0..<m { out[i] = storage[(rIdx + i) & mask] }
            rIdx += m
        }
        lock.unlock()
        return out
    }

    var available: Int {
        lock.lock(); defer { lock.unlock() }
        return wIdx - rIdx
    }
}

// ---------- ABL helpers ----------

func framesOf(_ bl: UnsafeMutableAudioBufferListPointer) -> Int {
    guard let b = bl.first, b.mData != nil, b.mDataByteSize > 0 else { return 0 }
    let ch = Int(max(b.mNumberChannels, 1))
    let interleaved = bl.count == 1 && ch > 1
    return Int(b.mDataByteSize) / (4 * (interleaved ? ch : 1))
}

// const ABL → mono mix
func monoFromABL(_ abl: UnsafePointer<AudioBufferList>?, frames: Int) -> [Float32] {
    var out = [Float32](repeating: 0, count: frames)
    guard let abl else { return out }
    let bl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: abl))
    var totalCh = 0
    for b in bl {
        let ch = Int(b.mNumberChannels)
        guard ch > 0, let d = b.mData, d != UnsafeMutableRawPointer(bitPattern: 1) else { continue }
        let p = d.assumingMemoryBound(to: Float32.self)
        if bl.count == 1 && ch > 1 {
            for f in 0..<frames {
                for c in 0..<ch { out[f] += p[f * ch + c] }
            }
            totalCh += ch
        } else {
            for f in 0..<frames { out[f] += p[f] }
            totalCh += 1
        }
    }
    if totalCh > 1 {
        for i in 0..<frames { out[i] /= Float32(totalCh) }
    }
    return out
}

// mono → mutable ABL (모든 채널에 동일 신호)
func fillABL(_ abl: UnsafeMutablePointer<AudioBufferList>, mono: [Float32], frames: Int) {
    let bl = UnsafeMutableAudioBufferListPointer(abl)
    mono.withUnsafeBufferPointer { src in
        for b in bl {
            guard let d = b.mData else { continue }
            let ch = Int(b.mNumberChannels)
            let p = d.assumingMemoryBound(to: Float32.self)
            if bl.count == 1 && ch > 1 {
                for f in 0..<frames {
                    for c in 0..<ch { p[f * ch + c] = src.baseAddress![f] }
                }
            } else {
                for f in 0..<frames { p[f] = src.baseAddress![f] }
            }
        }
    }
}

func zeroABL(_ abl: UnsafeMutablePointer<AudioBufferList>) {
    let bl = UnsafeMutableAudioBufferListPointer(abl)
    for b in bl {
        if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) }
    }
}

// ---------- 전역 컨텍스트 ----------

final class Ctx {
    let ringToBH2 = Ring(capacityPow2: 1 << 16)   // AEC 후 마이크 → BH2 (~1.4s @48k)
    let ringFar = Ring(capacityPow2: 1 << 16)     // BH16 루프백(원격) → VPIO 렌더
    let micMeter = Meter()    // VPIO 입력 콜백(AEC 후) 레벨
    let outMeter = Meter()    // BH2에 실제 기록한 레벨
    let refMeter = Meter()    // 원격 참조 신호(BH16) 레벨
    var farSamples: [Float32] = []
    var farPos = 0
    let farLock = NSLock()
    var mode = "a"
    var bh2Underruns = 0
    var farUnderruns = 0
    var recordFile: FileHandle? = nil
    let recordLock = NSLock()
}

let ctx = Ctx()

// ---------- IOProc / 콜백 (글로벌 상태만 사용) ----------

let bh2Proc: AudioDeviceIOProc = { _, _, inInputData, _, inOutputData, _, _ in
    let out = inOutputData
    let frames = framesOf(UnsafeMutableAudioBufferListPointer(out))
    if frames > 0 {
        var mono = ctx.ringToBH2.read(frames)
        if mono.count < frames {
            ctx.bh2Underruns += 1
            mono = [Float32](repeating: 0, count: frames)
        }
        fillABL(out, mono: mono, frames: frames)
        ctx.outMeter.process(mono)
        // 녹음: BH2에 쓴 신호 그대로
        if let fh = ctx.recordFile {
            mono.withUnsafeBufferPointer { bp in
                let data = Data(bytes: bp.baseAddress!, count: frames * 4)
                ctx.recordLock.lock()
                _ = try? fh.write(contentsOf: data)
                ctx.recordLock.unlock()
            }
        }
    }
    _ = inInputData
    return noErr
}

let bh16Proc: AudioDeviceIOProc = { _, _, inInputData, _, inOutputData, _, _ in
    // BH16 입력(루프백 = 우리가 쓴 원격 음성) → 참조 링
    do {
        let inp = inInputData
        let frames = framesOf(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inp)))
        if frames > 0 {
            let mono = monoFromABL(inp, frames: frames)
            ctx.ringFar.write(mono)
            ctx.refMeter.process(mono)
        }
    }
    // BH16 출력 ← 원격 음성 파일 (루프: 파일 끝나면 처음부터)
    do {
        let outp = inOutputData
        let frames = framesOf(UnsafeMutableAudioBufferListPointer(outp))
        if frames > 0 {
            ctx.farLock.lock()
            var mono = [Float32](repeating: 0, count: frames)
            let n = ctx.farSamples.count
            if n > 0 {
                for f in 0..<frames {
                    mono[f] = ctx.farSamples[ctx.farPos % n]
                    ctx.farPos = (ctx.farPos + 1) % n
                }
            }
            ctx.farLock.unlock()
            fillABL(outp, mono: mono, frames: frames)
        }
    }
    return noErr
}

// VPIO 입력 콜백: AEC 처리된 마이크
// 출력 유닛의 입력 콜백은 ioData가 nil로 온다. 콜백 안에서
// AudioUnitRender(element 1)로 입력 데이터를 직접 당겨온다(QA1733 패턴).
var gUnit: AudioUnit? = nil
var gScratch = [Float32](repeating: 0, count: 8192)
var gInputCbCount = 0
var gInputCbFrames = 0
var gInputCbNoData = 0
var gRenderErr: OSStatus = 0
var gRenderErrCount = 0
let vpioInputProc: AURenderCallback = { _, ioActionFlags, inTimeStamp, _, inNumberFrames, ioData in
    gInputCbCount += 1
    gInputCbFrames = Int(inNumberFrames)
    guard let unit = gUnit else { gInputCbNoData += 1; return noErr }
    let frames = Int(inNumberFrames)
    guard frames > 0, frames <= gScratch.count else { return noErr }
    gScratch.withUnsafeMutableBufferPointer { bp in
        var abl = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(frames * 4),
                mData: bp.baseAddress))
        let st = AudioUnitRender(unit, ioActionFlags, inTimeStamp, 1, inNumberFrames, &abl)
        if st != noErr { gRenderErr = st; gRenderErrCount += 1; return }
        var mono = [Float32](repeating: 0, count: frames)
        for i in 0..<frames { mono[i] = bp[i] }
        ctx.micMeter.process(mono)
        ctx.ringToBH2.write(mono)
    }
    return noErr
}

// 렌더용 스크래치 버퍼 (ioData의 mData가 nil일 때)
var gOutScratch = [Float32](repeating: 0, count: 8192)
var gNilDataCount = 0

// VPIO 출력 렌더: b면 참조(원격) 신호, 아니면 무음
var gRenderCbCount = 0
var gRenderCbFrames = 0
let vpioRenderProc: AURenderCallback = { _, _, _, _, inNumberFrames, ioData in
    gRenderCbCount += 1
    gRenderCbFrames = Int(inNumberFrames)
    guard let io = ioData else { return noErr }
    let frames = Int(inNumberFrames)
    guard frames > 0, frames * 2 <= gOutScratch.count else { return noErr }
    var mono: [Float32]
    if ctx.mode == "b" {
        mono = ctx.ringFar.read(frames)
        if mono.count < frames {
            ctx.farUnderruns += 1
            mono = [Float32](repeating: 0, count: frames)
        }
    } else {
        mono = [Float32](repeating: 0, count: frames)
    }
    let bl = UnsafeMutableAudioBufferListPointer(io)
    // mData nil 여부 확인 후 필요하면 스크래치 할당
    var needScratch = false
    for b in bl where b.mData == nil { needScratch = true }
    if needScratch {
        gNilDataCount += 1
        gOutScratch.withUnsafeMutableBytes { raw in
            let base = raw.baseAddress!
            let ablPtr = UnsafeMutableRawPointer(io).assumingMemoryBound(to: AudioBufferList.self)
            let n = Int(ablPtr.pointee.mNumberBuffers)
            for bi in 0..<n {
                var buf = ablPtr.pointee.mBuffers
                let p = base.advanced(by: bi * 8192 * 4).assumingMemoryBound(to: Float32.self)
                for f in 0..<frames { p[f] = mono[f] }
                buf.mData = UnsafeMutableRawPointer(p)
                buf.mDataByteSize = UInt32(frames * 4)
                buf.mNumberChannels = 1
                ablPtr.pointee.mBuffers = buf
            }
        }
    } else {
        fillABL(io, mono: mono, frames: frames)
    }
    return noErr
}

// ---------- aggregate ----------

func createAggregate(micUID: String, spkUID: String) -> AudioDeviceID? {
    let subs: [[String: Any]] = [
        [kAudioSubDeviceUIDKey as String: micUID, kAudioSubDeviceDriftCompensationKey as String: 1],
        [kAudioSubDeviceUIDKey as String: spkUID, kAudioSubDeviceDriftCompensationKey as String: 0],
    ]
    let desc: [String: Any] = [
        kAudioAggregateDeviceNameKey as String: "maecrelay-agg",
        kAudioAggregateDeviceUIDKey as String: "maecrelay-agg-uid",
        kAudioAggregateDeviceIsPrivateKey as String: 1,
        kAudioAggregateDeviceMainSubDeviceKey as String: spkUID,
        kAudioAggregateDeviceSubDeviceListKey as String: subs,
    ]
    var aggID: AudioDeviceID = 0
    let st = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggID)
    guard st == noErr else {
        print("WARN aggregate 생성 실패: \(st)")
        return nil
    }
    return aggID
}

// ---------- main ----------

var mode = "a"
var duration = 0.0
var farPath = ""
var bypassFlag = false
var recordPath = ""
var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    let a = args[i]
    switch a {
    case "--mode": i += 1; if i < args.count { mode = args[i] }
    case "--duration": i += 1; if i < args.count { duration = Double(args[i]) ?? 0 }
    case "--farfile": i += 1; if i < args.count { farPath = args[i] }
    case "--bypass": bypassFlag = true
    case "--record": i += 1; if i < args.count { recordPath = args[i] }
    default: break
    }
    i += 1
}
ctx.mode = mode

let micUID = "AppleUSBAudioEngine:ShenZhen Maono Technology Co., Ltd.:Maono Dynamic Microphone:SERIAL:1,2"
let spkUID = "DISPLAY-UID"
let bh2UID = "BlackHole2ch_UID"
let bh16UID = "BlackHole16ch_UID"

guard let micID = uidToID(micUID) else { fail("마이크(Maono)를 못 찾음") }
guard let spkID = uidToID(spkUID) else { fail("스피커(DELL)를 못 찾음") }
guard let bh2ID = uidToID(bh2UID) else { fail("BlackHole 2ch를 못 찾음") }

print("MODE=\(mode) duration=\(duration > 0 ? String(duration) : "until-CtrlC") farfile=\(farPath.isEmpty ? "-" : farPath)")
print("mic=\(deviceName(micID) ?? "?") rate=\(nominalRate(micID))")
print("spk=\(deviceName(spkID) ?? "?") rate=\(nominalRate(spkID))")
print("bh2=\(deviceName(bh2ID) ?? "?") rate=\(nominalRate(bh2ID))")

// farfile 로드 (b/t 모드)
if mode == "b" || mode == "t" {
    guard !farPath.isEmpty else { fail("mode \(mode)에는 --farfile 이 필요하다") }
    let url = URL(fileURLWithPath: farPath)
    guard let data = try? Data(contentsOf: url), data.count % 4 == 0 else { fail("farfile 읽기 실패: \(farPath)") }
    ctx.farSamples = data.withUnsafeBytes { raw in
        let p = raw.bindMemory(to: Float32.self)
        return Array(p)
    }
    print("far samples=\(ctx.farSamples.count) (\(Double(ctx.farSamples.count) / 48000.0)s @48k)")
}

// 녹음 파일 열기
if !recordPath.isEmpty {
    FileManager.default.createFile(atPath: recordPath, contents: nil)
    guard let fh = FileHandle(forWritingAtPath: recordPath) else { fail("녹음 파일 열기 실패: \(recordPath)") }
    ctx.recordFile = fh
    print("녹음: \(recordPath)")
}

// ---------- 유닛/장치 구성 ----------

var unit: AudioUnit?
var aggID: AudioDeviceID? = nil
var bh16ID: AudioDeviceID? = nil
var bh16ProcID: AudioDeviceIOProcID? = nil
var bh2ProcID: AudioDeviceIOProcID? = nil

func teardown() {
    if let u = unit {
        AudioOutputUnitStop(u)
        AudioUnitUninitialize(u)
        AudioComponentInstanceDispose(u)
    }
    if let p = bh2ProcID {
        AudioDeviceStop(bh2ID, p)
        AudioDeviceDestroyIOProcID(bh2ID, p)
    }
    if let d = bh16ID, let p = bh16ProcID {
        AudioDeviceStop(d, p)
        AudioDeviceDestroyIOProcID(d, p)
    }
    if let a = aggID {
        AudioHardwareDestroyAggregateDevice(a)
    }
}

func startBH2() {
    if setNominalRate(bh2ID, 48000) != noErr {
        print("WARN BH2 샘플레이트 48k 설정 실패 (현재 \(nominalRate(bh2ID)))")
    }
    must(AudioDeviceCreateIOProcID(bh2ID, bh2Proc, nil, &bh2ProcID), "BH2 IOProc")
    must(AudioDeviceStart(bh2ID, bh2ProcID), "BH2 start")
    print("BH2 writer 시작 (rate=\(nominalRate(bh2ID)))")
}

func makeUnit(subtype: UInt32) -> AudioUnit {
    var desc = AudioComponentDescription(
        componentType: kAudioUnitType_Output,
        componentSubType: OSType(subtype),
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0)
    guard let comp = AudioComponentFindNext(nil, &desc) else { fail("오디오 유닛 컴포넌트 없음 (subtype \(subtype))") }
    var u: AudioUnit?
    must(AudioComponentInstanceNew(comp, &u), "AudioComponentInstanceNew")
    guard let unit = u else { fail("유닛 nil") }
    return unit
}

var fmt = AudioStreamBasicDescription(
    mSampleRate: 48000,
    mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
    mBytesPerPacket: 4,
    mFramesPerPacket: 1,
    mBytesPerFrame: 4,
    mChannelsPerFrame: 1,
    mBitsPerChannel: 32,
    mReserved: 0)
let fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

func configIO(_ u: AudioUnit, inputOn: Bool, outputOn: Bool, device: AudioDeviceID?) {
    if let dev = device {
        var d = dev
        must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &d, UInt32(MemoryLayout<AudioObjectID>.size)), "CurrentDevice")
    }
    var enIn: UInt32 = inputOn ? 1 : 0
    must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enIn, 4), "EnableIO(input)")
    var enOut: UInt32 = outputOn ? 1 : 0
    must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enOut, 4), "EnableIO(output)")
    if inputOn {
        must(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fmt, fmtSize), "StreamFormat(in)")
        var cb = AURenderCallbackStruct(inputProc: vpioInputProc, inputProcRefCon: nil)
        must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "SetInputCallback")
    }
    if outputOn {
        must(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, fmtSize), "StreamFormat(out)")
        var rc = AURenderCallbackStruct(inputProc: vpioRenderProc, inputProcRefCon: nil)
        must(AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &rc, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "SetRenderCallback")
    }
}

switch mode {
case "raw":
    let u = makeUnit(subtype: kAudioUnitSubType_HALOutput)
    configIO(u, inputOn: true, outputOn: false, device: micID)
    unit = u
case "a":
    let u = makeUnit(subtype: kAudioUnitSubType_VoiceProcessingIO)
    configIO(u, inputOn: true, outputOn: true, device: nil)
    unit = u
case "ai":
    let u = makeUnit(subtype: kAudioUnitSubType_VoiceProcessingIO)
    configIO(u, inputOn: true, outputOn: false, device: micID)
    unit = u
case "b":
    // VPIO는 aggregate CurrentDevice를 거부한다(-10851 실측).
    // CurrentDevice 미지정 = 시스템 기본(Maono 입력/DELL 출력).
    // far 음성을 BH16에 쓰면 루프백 입력으로 돌아오고, 이를
    // VPIO 출력 버스에 렌더해 DELL에서 실제 재생 = AEC 참조.
    let u = makeUnit(subtype: kAudioUnitSubType_VoiceProcessingIO)
    configIO(u, inputOn: true, outputOn: true, device: nil)
    unit = u
    let b16 = uidToID(bh16UID)
    guard b16 != nil else { fail("BlackHole 16ch를 못 찾음") }
    bh16ID = b16
    if setNominalRate(b16!, 48000) != noErr {
        print("WARN BH16 샘플레이트 48k 설정 실패 (현재 \(nominalRate(b16!)))")
    }
    must(AudioDeviceCreateIOProcID(b16!, bh16Proc, nil, &bh16ProcID), "BH16 IOProc")
    must(AudioDeviceStart(b16!, bh16ProcID), "BH16 start")
    print("BH16 far 재생 시작 (rate=\(nominalRate(b16!)))")
case "t":
    // 검증/bypass 기준선 모드: HALOutput 입출력. farfile을 BH16→기본
    // 출력(DELL)으로 렌더해 물리 재생하고, 마이크 입력(AEC 없음)을
    // BH2+녹음에 기록한다. b 모드와 동일한 체인의 처리 없음 버전.
    let u = makeUnit(subtype: kAudioUnitSubType_HALOutput)
    configIO(u, inputOn: true, outputOn: true, device: nil)
    unit = u
    let b16 = uidToID(bh16UID)
    guard b16 != nil else { fail("BlackHole 16ch를 못 찾음") }
    bh16ID = b16
    if setNominalRate(b16!, 48000) != noErr {
        print("WARN BH16 샘플레이트 48k 설정 실패")
    }
    must(AudioDeviceCreateIOProcID(b16!, bh16Proc, nil, &bh16ProcID), "BH16 IOProc")
    must(AudioDeviceStart(b16!, bh16ProcID), "BH16 start")
    print("BH16 far 재생 시작 (rate=\(nominalRate(b16!)))")
default:
    fail("알 수 없는 모드: \(mode) (raw|a|ai|b|t)")
}

guard let u = unit else { fail("유닛 없음") }

// VPIO면 AGC 끄고 AEC 강제 (레벨 비교 왜곡 방지)
if mode != "raw" {
    var agc: UInt32 = 0
    let st = AudioUnitSetProperty(u, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0, &agc, 4)
    print("AGC off: \(st == noErr ? "ok" : "skip(\(st))")")
    var bypass: UInt32 = bypassFlag ? 1 : 0
    let st2 = AudioUnitSetProperty(u, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 0, &bypass, 4)
    print("bypass \(bypassFlag ? "ON(처리없음)" : "off"): \(st2 == noErr ? "ok" : "skip(\(st2))")")
}

must(AudioUnitInitialize(u), "AudioUnitInitialize")
gUnit = u
must(AudioOutputUnitStart(u), "AudioOutputUnitStart")
startBH2()
print("RUNNING")

// ---------- 실행 루프 ----------

let t0 = Date()
var tick = 0
while gRunning {
    Thread.sleep(forTimeInterval: 1.0)
    tick += 1
    if !gRunning { break }
    if duration > 0 && Date().timeIntervalSince(t0) >= duration { break }
    if tick % 2 == 0 {
        let (mp, mr, mc) = ctx.micMeter.drain()
        let (op, orr, oc) = ctx.outMeter.drain()
        let (rp, rr, rc) = ctx.refMeter.drain()
        print(String(format: "[%3ds] mic %7.1f/%7.1f (%d)  bh2 %7.1f/%7.1f (%d)  ref %7.1f/%7.1f (%d)  underrun bh2=%d far=%d ringBH2=%d ringFar=%d inCb=%d inCbFrames=%d noData=%d",
                     tick, mp, mr, mc, op, orr, oc, rp, rr, rc,
                     ctx.bh2Underruns, ctx.farUnderruns, ctx.ringToBH2.available, ctx.ringFar.available, gInputCbCount, gInputCbFrames, gInputCbNoData))
        print(String(format: "        renderCb=%d frames=%d", gRenderCbCount, gRenderCbFrames))
    }
}

// 남은 미터 drain
_ = ctx.micMeter.drain(); _ = ctx.outMeter.drain(); _ = ctx.refMeter.drain()
if let fh = ctx.recordFile {
    ctx.recordLock.lock()
    try? fh.close()
    ctx.recordLock.unlock()
    print("녹음 종료")
}
let (mp, mr, mc) = ctx.micMeter.overall()
let (op, orr, oc) = ctx.outMeter.overall()
let (rp, rr, rc) = ctx.refMeter.overall()
print(String(format: "OVERALL mic peak=%.1f rms=%.1f cb=%d", mp, mr, mc))
print(String(format: "OVERALL bh2 peak=%.1f rms=%.1f cb=%d", op, orr, oc))
print(String(format: "OVERALL ref peak=%.1f rms=%.1f cb=%d", rp, rr, rc))
print("STATUS completed mode=\(mode)")

teardown()
print("종료")
