import AVFoundation
import CoreAudio
import AudioUnit
import Foundation
import Darwin

// ============================================================
// speexrelay — macOS 통화 에코 제거 speexdsp AEC 중계 (VPIO 대체)
//
// 구조:
//   Maono PD300X ─HAL입력유닛→ ringMic ─┐
//                                        ├→ speex AEC 스레드 → ringOut → BH2 (전화앱 마이크)
//   BH16(전화앱 출력) ─루프백→ ringRef ──┘        ↑
//        └────────→ ringRefSpk → HAL출력유닛 → DELL (물리 재생)
//
// 모드:
//   aec    : speex_echo + speex_preprocess(잔여 에코 억제) 적용 (기본)
//   bypass : 같은 체인, AEC 없이 통과 (대조 기준선)
//
// speex는 48k에서 frame=480(10ms), tail=400ms(19200) 기본.
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

// ---------- speexdsp C 인터페이스 (CSpeexDsp 모듈) ----------

import CSpeexDsp

// speex_echo.h
let SPEEX_ECHO_SET_SAMPLING_RATE: CInt = 24
// speex_preprocess.h
let SPEEX_PREPROCESS_SET_DENOISE: CInt = 0
let SPEEX_PREPROCESS_SET_AGC: CInt = 2
let SPEEX_PREPROCESS_SET_NOISE_SUPPRESS: CInt = 18
let SPEEX_PREPROCESS_SET_ECHO_SUPPRESS: CInt = 20
let SPEEX_PREPROCESS_SET_ECHO_SUPPRESS_ACTIVE: CInt = 22
let SPEEX_PREPROCESS_SET_ECHO_STATE: CInt = 24

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
    var r: Float64 = rate
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
    private var totalSumSquares: Double = 0
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
        totalSumSquares += ss
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
        let rmsDb = totalFrames > 0 ? 10 * log10(max(totalSumSquares / Double(totalFrames), 1e-12)) : -999
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

// 활성 채널(신호가 실재하는 채널)만 골라 평균한다.
//
// BlackHole 16ch 같은 다채널 장치는 전화앱이 앞 2채널에만 쓰고 나머지 14채널은
// 무음이다. 전체 채널 수로 나누면 신호가 8분의 1(-18 dB)로 줄어든다.
// 2026-09-12 실통화에서 상대 목소리가 작게 들린 원인이 이것이었고,
// 스피커가 조용해져 에코가 준 것을 AEC 효과로 오인하게 만들었다.
func monoFromABL(_ abl: UnsafePointer<AudioBufferList>?, frames: Int) -> [Float32] {
    var out = [Float32](repeating: 0, count: frames)
    guard let abl else { return out }
    let bl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: abl))
    var activeCh = 0
    for b in bl {
        let ch = Int(b.mNumberChannels)
        guard ch > 0, let d = b.mData else { continue }
        let p = d.assumingMemoryBound(to: Float32.self)
        if bl.count == 1 && ch > 1 {
            // 인터리브드 다채널: 채널별로 무음 여부를 보고 실신호 채널만 더한다
            for c in 0..<ch {
                var silent = true
                var f = 0
                while f < frames {
                    if p[f * ch + c] != 0 { silent = false; break }
                    f += 1
                }
                if silent { continue }
                for f in 0..<frames { out[f] += p[f * ch + c] }
                activeCh += 1
            }
        } else {
            var silent = true
            for f in 0..<frames where p[f] != 0 { silent = false; break }
            if !silent {
                for f in 0..<frames { out[f] += p[f] }
                activeCh += 1
            }
        }
    }
    if activeCh > 1 {
        for i in 0..<frames { out[i] /= Float32(activeCh) }
    }
    return out
}

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

// ---------- 전역 상태 ----------

final class Ctx {
    let ringMic = Ring(capacityPow2: 1 << 16)     // Maono 원본 → AEC
    let ringRef = Ring(capacityPow2: 1 << 16)     // BH16 루프백 참조 → AEC
    let ringRefSpk = Ring(capacityPow2: 1 << 16)  // BH16 루프백 참조 → DELL 렌더
    let ringOut = Ring(capacityPow2: 1 << 16)     // AEC 출력 → BH2
    let micMeter = Meter()
    let refMeter = Meter()
    let outMeter = Meter()
    var mode = "aec"
    // ref 지연선(샘플): mic와 ref의 벌크 경로 지연 차를 여기서 흡수한다.
    // 측정값: 스피커→마이크 경로가 ref(전기적 루프백)보다 약 359ms 늦다.
    var refDelaySamples: Int = 0
    var bh2Underruns = 0
    var spkUnderruns = 0
    var refDropped = 0        // ref 단독 백로그로 버린 샘플 누적
    // 캘리브레이션용 신호 수집구.
    // 캘리브레이션 스레드가 링버퍼를 직접 읽으면 본 루프와 소비 경합이 난다.
    // 대신 본 루프가 처리 중인 프레임의 '사본'을 여기에 흘려보낸다.
    let calLock = NSLock()
    var calMic = [Float32]()
    var calRef = [Float32]()
    var calCollecting = false
    // 캘리브레이션이 구한 지연. 본 루프가 프레임 경계에서 집어간다.
    var pendingRefDelay: Int? = nil
    var recordFile: FileHandle? = nil
    let recordLock = NSLock()
    var aecFrames = 0
    var aecRefZeroFrames = 0   // 참조가 전부 0이었던 프레임
    // 워커 깨우기(폴링 폐지: usleep 폴링은 생산 속도를 못 따라가
    // mic/ref 링 백로그 차가 흔들려 AEC 시간 정렬이 깨진다)
    let wake = DispatchSemaphore(value: 0)
    // 측정용 far 재생 (BH16 출력에 루프로 기록)
    var farSamples: [Float32] = []
    var farPos = 0
}

let ctx = Ctx()

// ---------- 콜백 ----------

// Maono HAL 입력: 출력유닛의 입력 콜백(ioData nil) → AudioUnitRender(element 1)
var gMicUnit: AudioUnit? = nil
var gMicCbCount = 0
var gMicTotalFrames = 0
var gMicLastCbFrames = 0
var gMicRenderErr: OSStatus = 0
var gMicRenderErrCount = 0
let micInputProc: AURenderCallback = { _, ioActionFlags, inTimeStamp, _, inNumberFrames, _ in
    gMicCbCount += 1
    gMicTotalFrames += Int(inNumberFrames)
    gMicLastCbFrames = Int(inNumberFrames)
    guard let unit = gMicUnit else { return noErr }
    let frames = Int(inNumberFrames)
    guard frames > 0, frames <= 16384 else { return noErr }
    var scratch = [Float32](repeating: 0, count: frames)
    scratch.withUnsafeMutableBufferPointer { bp in
        var abl = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(frames * 4),
                mData: bp.baseAddress))
        let st = AudioUnitRender(unit, ioActionFlags, inTimeStamp, 1, inNumberFrames, &abl)
        if st != noErr { gMicRenderErr = st; gMicRenderErrCount += 1; return }
        var mono = [Float32](repeating: 0, count: frames)
        for i in 0..<frames { mono[i] = bp[i] }
        ctx.micMeter.process(mono)
        ctx.ringMic.write(mono)
        ctx.wake.signal()
    }
    return noErr
}

// BH16 IOProc: 루프백 입력(전화앱이 BH16에 쓴 신호)을 참조 두 곳으로
// + 측정 모드에서는 우리가 far 음성을 BH16 출력에 쓴다(루프백 발생용)
var gFarWriteFrames = 0
let bh16Proc: AudioDeviceIOProc = { _, _, inInputData, _, inOutputData, _, _ in
    let inp = inInputData
    let frames = framesOf(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inp)))
    if frames > 0 {
        let mono = monoFromABL(inp, frames: frames)
        ctx.ringRef.write(mono)
        ctx.ringRefSpk.write(mono)
        ctx.refMeter.process(mono)
        ctx.wake.signal()
   }
    // far 음성을 BH16 출력으로 (측정 모드, 파일 루프)
    do {
        let op = inOutputData
        let oframes = framesOf(UnsafeMutableAudioBufferListPointer(op))
        if oframes > 0, !ctx.farSamples.isEmpty {
            var mono = [Float32](repeating: 0, count: oframes)
            let n = ctx.farSamples.count
            for f in 0..<oframes {
                mono[f] = ctx.farSamples[ctx.farPos % n]
                ctx.farPos = (ctx.farPos + 1) % n
            }
            fillABL(op, mono: mono, frames: oframes)
            gFarWriteFrames += oframes
        }
    }
    return noErr
}

// BH2 IOProc: AEC 결과를 전화앱 마이크로
let bh2Proc: AudioDeviceIOProc = { _, _, _, _, inOutputData, _, _ in
    let out = inOutputData
    let frames = framesOf(UnsafeMutableAudioBufferListPointer(out))
    if frames > 0 {
        var mono = ctx.ringOut.read(frames)
        if mono.count < frames {
            ctx.bh2Underruns += 1
            mono = [Float32](repeating: 0, count: frames)
        }
        fillABL(out, mono: mono, frames: frames)
        ctx.outMeter.process(mono)
        if let fh = ctx.recordFile {
            mono.withUnsafeBufferPointer { bp in
                let data = Data(bytes: bp.baseAddress!, count: frames * 4)
                ctx.recordLock.lock()
                _ = try? fh.write(contentsOf: data)
                ctx.recordLock.unlock()
            }
        }
    }
    return noErr
}

// DELL 렌더: 참조 신호를 물리 스피커로
//
// refSpk 링버퍼에 백로그 상한이 없으면 BH16 쓰기가 DELL 읽기보다 빨라
// 버퍼가 계속 쌓이고, 상대 목소리가 점점 늦게 들린다.
// 2026-09-12 실통화에서 실측: refSpk 16896(352ms) → 25088(523ms) → 31232(651ms).
// 사용자가 "목소리가 느리다"고 한 원인. 상한을 넘으면 오래된 것을 버려
// 지연을 일정하게 유지한다.
let spkMaxBacklog = 4800   // 100ms @48k
var gSpkCbCount = 0
var gSpkDropped = 0
let spkRenderProc: AURenderCallback = { _, _, _, _, inNumberFrames, ioData in
    gSpkCbCount += 1
    guard let io = ioData else { return noErr }
    let frames = Int(inNumberFrames)
    guard frames > 0 else { return noErr }
    // 쌓인 백로그가 상한을 넘으면 초과분을 버린다(오래된 샘플 폐기).
    let avail = ctx.ringRefSpk.available
    if avail > spkMaxBacklog + frames {
        let drop = avail - spkMaxBacklog
        _ = ctx.ringRefSpk.read(drop)
        gSpkDropped += drop
    }
    var mono = ctx.ringRefSpk.read(frames)
    if mono.count < frames {
        ctx.spkUnderruns += 1
        mono = [Float32](repeating: 0, count: frames)
    }
    fillABL(io, mono: mono, frames: frames)
    return noErr
}

// ---------- speex AEC 워커 ----------

final class SpeexAecWorker {
    let frameSize: Int
    let tailMs: Int
    let rate: Int
    let bypass: Bool
    // 잔여 에코 억제기 세기(dB, 음수).
    // esupActive는 상대가 말하는 동안(더블토크 포함) 적용된다.
    // 기본값은 speexdsp 기본과 동일. 2026-09-12에 -15와 -30을 재봤으나
    // 더블토크 출력이 -48.9 대 -48.4로 차이가 없었다. 나머지 값은 미측정.
    var echoSuppress: Int = -40
    var echoSuppressActive: Int = -15
    var autoCalibrate: Bool = false
    private var st: OpaquePointer? = nil
    private var pre: OpaquePointer? = nil
    private var thread: Thread? = nil
    private var running = true
    private var loopExited = false
    private let exitLock = NSLock()
    private let exited = DispatchSemaphore(value: 0)

    init(frameSize: Int, tailMs: Int, rate: Int, bypass: Bool) {
        self.frameSize = frameSize
        self.tailMs = tailMs
        self.rate = rate
        self.bypass = bypass
    }

    // 자기 정합: mic/ref를 쌓아 상관으로 벌크 지연을 잡는다.
    // ref를 d만큼 지연시켜 mic와 최대 상관이 되는 d를 찾는다.
    //
    // 실통화 대응(2026-09-12): 기존 구현은 시작 후 3초 안에 1회만 시도하고
    // 조용하면 "레벨 부족"으로 포기했다. 통화를 걸면 그 순간에는 상대가 아직
    // 말하지 않으므로 실통화에서는 항상 실패했다(실측 확인). 측정 모드는
    // farfile이 즉시 재생되어 이 문제가 드러나지 않았다.
    //
    // 이제 신호가 충분해질 때까지 최대 waitLimit초 동안 기다린다. 그동안은
    // refDelay 0으로 통과시키고, 캘리브레이션이 성공하면 그때부터 적용한다.
    private func calibrateDelay(waitLimit: TimeInterval = 90.0) -> Int {
        let need = rate * 3 / 2          // 1.5초
        let maxDelay = rate / 2          // 탐색 상한 500ms
        let minRms: Float32 = 3e-4       // 이 아래면 '조용함'으로 보고 계속 대기
        let t0 = Date()
        var announced = false

        func rms(_ x: [Float32]) -> Float32 {
            (x.reduce(0) { $0 + $1 * $1 } / Float32(max(x.count, 1))).squareRoot()
        }

        ctx.calLock.lock(); ctx.calCollecting = true; ctx.calLock.unlock()
        defer {
            ctx.calLock.lock()
            ctx.calCollecting = false
            ctx.calMic.removeAll(); ctx.calRef.removeAll()
            ctx.calLock.unlock()
        }

        while Date().timeIntervalSince(t0) < waitLimit {
            if !running { return ctx.refDelaySamples }
            Thread.sleep(forTimeInterval: 0.25)

            ctx.calLock.lock()
            let haveMic = ctx.calMic.count
            let haveRef = ctx.calRef.count
            var micBuf = [Float32]()
            var refBuf = [Float32]()
            if haveMic >= need && haveRef >= need {
                micBuf = Array(ctx.calMic.suffix(need))
                refBuf = Array(ctx.calRef.suffix(need))
            }
            ctx.calLock.unlock()

            guard micBuf.count == need, refBuf.count == need else { continue }

            let mR = rms(micBuf), rR = rms(refBuf)

            // 참조나 마이크가 조용하면 아직 캘리브레이션할 수 없다. 계속 기다린다.
            if mR < minRms || rR < minRms {
                if !announced {
                    print("정합 캘리브레이션: 신호 대기 중 (통화가 시작되면 자동 보정)")
                    announced = true
                }
                continue
            }

            let n = need
            let step = rate / 1000
            var bestLag = 0
            var bestScore: Float = -2.0
            for d in stride(from: 0, through: maxDelay, by: step) {
                var dot: Float32 = 0
                var i = d
                while i < n {
                    dot += micBuf[i] * refBuf[i - d]
                    i += step  // 서브샘플링으로 계산량 절감
                }
                let denom = Float32((n - d) / step)
                let score = dot / denom / (mR * rR)
                if score > bestScore {
                    bestScore = score
                    bestLag = d
                }
            }
            // 상관이 약하면 신뢰할 수 없다. 더 좋은 구간을 기다린다.
            if bestScore < 0.10 {
                continue
            }
            let elapsed = Date().timeIntervalSince(t0)
            print(String(format: "정합 캘리브레이션: lag=%d samples (%.1f ms) corr=%.3f (%.0fs 후)",
                         bestLag, Double(bestLag) * 1000.0 / Double(rate), bestScore, elapsed))
            return bestLag
        }
        print("정합 캘리브레이션: \(Int(waitLimit))초 내 유효 신호 없음 — refdelay 0 유지")
        return ctx.refDelaySamples
    }

    func start() {
        // 캘리브레이션은 신호가 올 때까지 최대 90초 기다리므로 여기서 블로킹하면
        // 오디오 경로가 그동안 멈춘다. 백그라운드로 돌리고 본 루프는 즉시 시작한다.
        // 보정 전에는 refDelay 0으로 통과하고, 값이 정해지면 그 시점부터 반영된다.
        if autoCalibrate {
            let ct = Thread { [self] in
                let lag = calibrateDelay()
                if lag != ctx.refDelaySamples {
                    ctx.pendingRefDelay = lag
                }
            }
            ct.stackSize = 1 << 20
            ct.start()
        }
        if !bypass {
            let tail = rate * tailMs / 1000
            guard let es = speex_echo_state_init(CInt(frameSize), CInt(tail)) else {
                fail("speex_echo_state_init 실패")
            }
            st = es
            var r = CInt(rate)
            _ = speex_echo_ctl(es, SPEEX_ECHO_SET_SAMPLING_RATE, &r)
            guard let ps = speex_preprocess_state_init(CInt(frameSize), CInt(rate)) else {
                fail("speex_preprocess_state_init 실패")
            }
            pre = ps
            // AGC 끔(레벨 측정 왜곡 방지)
            var agc: CInt = 0
            _ = speex_preprocess_ctl(ps, SPEEX_PREPROCESS_SET_AGC, &agc)
            // 잔여 에코 억제: 전처리기에 에코 상태 연결
            // SET_ECHO_STATE는 SpeexEchoState 포인터 '값'을 요구한다(이중 포인터 아님).
            _ = speex_preprocess_ctl(ps, SPEEX_PREPROCESS_SET_ECHO_STATE, UnsafeMutableRawPointer(mutating: UnsafeRawPointer(es)))
            var den: CInt = 1
            _ = speex_preprocess_ctl(ps, SPEEX_PREPROCESS_SET_DENOISE, &den)
            var ns: CInt = -40
            _ = speex_preprocess_ctl(ps, SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &ns)
            var esup: CInt = CInt(echoSuppress)
            _ = speex_preprocess_ctl(ps, SPEEX_PREPROCESS_SET_ECHO_SUPPRESS, &esup)
            var esupA: CInt = CInt(echoSuppressActive)
            _ = speex_preprocess_ctl(ps, SPEEX_PREPROCESS_SET_ECHO_SUPPRESS_ACTIVE, &esupA)
            print("speex AEC init: frame=\(frameSize) tail=\(tail) rate=\(rate) esup=\(esup) esupActive=\(esupA)")
        } else {
            print("bypass 모드: AEC 없이 통과")
        }
        let t = Thread { [self] in self.loop() }
        t.stackSize = 1 << 20
        t.start()
        thread = t
    }

    private func loop() {
        var accumMic = [Float32]()
        var accumRef = [Float32]()
        var i16Mic = [Int16](repeating: 0, count: frameSize)
        var i16Ref = [Int16](repeating: 0, count: frameSize)
        var i16Out = [Int16](repeating: 0, count: frameSize)
        var outFrame = [Float32](repeating: 0, count: frameSize)
        // ref 지연선 버퍼: ref를 refDelaySamples만큼 지연시켜 mic와 정렬.
        // 지연 못 만큼의 0으로 채워 시작(선입선출).
        var refDelayBuf = [Float32](repeating: 0, count: max(0, ctx.refDelaySamples))
        // 시작 시 쌓여 있는 백로그를 버린다(정렬 붕괴 방지).
        _ = ctx.ringRef.read(ctx.ringRef.available)
        _ = ctx.ringMic.read(ctx.ringMic.available)
        let refMaxBacklog = 4800   // 100ms
        let micMaxBacklog = 9600   // 200ms
        while running {
            // 백로그 제한 1: mic/ref 공통 백로그.
            // 둘 다 밀려 있으면 같은 양만큼 버려야 상대 지연이 보존된다.
            let backlog = min(ctx.ringRef.available, ctx.ringMic.available)
            if backlog > micMaxBacklog {
                let drop = backlog - micMaxBacklog
                _ = ctx.ringRef.read(drop)
                _ = ctx.ringMic.read(drop)
            }
            // 백로그 제한 2: ref 단독 폭주.
            //
            // 위 min() 판정은 mic가 비어 있으면 0이 되어 ref가 아무리 쌓여도
            // 걸리지 않는다. 실통화에서 ref만 15360샘플(320ms)로 고정된 채
            // mic는 0~400인 상태가 관측됐다. 참조가 마이크보다 320ms 늦게
            // 들어가면 AEC는 시간축이 어긋나 에코를 제거할 수 없다.
            // (2026-09-12 실통화: refZero 86%, 억제량 0~3.7 dB)
            //
            // mic와 무관하게 ref 자체 백로그가 상한을 넘으면 오래된 것을 버린다.
            if ctx.ringRef.available > refMaxBacklog {
                let drop = ctx.ringRef.available - refMaxBacklog
                _ = ctx.ringRef.read(drop)
                ctx.refDropped += drop
            }
            // mic와 ref를 같은 길이로 전진시킨다.
            // mic는 실제 도착한 만큼만 읽는다(Ring.read는 부족분을 0으로
            // 패딩해 반환하므로 want를 available로 잘라야 한다. 0패딩 마이크
            // 프레임이 AEC 적응을 망친다). ref 부족분만 의도적으로 0 패딩.
            let want = max(frameSize - accumMic.count, 0)
            if want > 0 {
                accumMic += ctx.ringMic.read(min(want, ctx.ringMic.available))
            }
            let refAvail = ctx.ringRef.available
            let refNeed = accumMic.count - accumRef.count
            if refNeed > 0 {
                let take = min(refNeed, refAvail)
                var fresh = ctx.ringRef.read(take)
                // 지연선 통과: 출력은 (지연 못 + 새 입력 - 지연 못) = 1프레임씩 밀린 과거 값
                if refDelayBuf.count > 0 || ctx.refDelaySamples > 0 {
                    refDelayBuf += fresh
                    let outN = refDelayBuf.count - ctx.refDelaySamples
                    if outN > 0 {
                        fresh = Array(refDelayBuf.prefix(outN))
                        refDelayBuf.removeFirst(outN)
                    } else {
                        fresh = []
                    }
                }
                accumRef += fresh
                if accumRef.count < accumMic.count {
                    accumRef += [Float32](repeating: 0, count: accumMic.count - accumRef.count)
                    if take == 0 { ctx.aecRefZeroFrames += 1 }
                }
            }
            while accumMic.count >= frameSize, running {
                // 캘리브레이션 스레드가 결과를 내놓았으면 프레임 경계에서 반영한다.
                if let pd = ctx.pendingRefDelay {
                    ctx.pendingRefDelay = nil
                    if pd != ctx.refDelaySamples {
                        ctx.refDelaySamples = pd
                        refDelayBuf = [Float32](repeating: 0, count: max(0, pd))
                        if let es = st { _ = speex_echo_state_reset(es) }
                        print(String(format: "refdelay 적용: %d samples (%.1f ms) — AEC 상태 리셋",
                                     pd, Double(pd) / 48.0))
                    }
                }
                // 캘리브레이션이 수집 중이면 처리할 프레임의 사본을 넘긴다.
                // (링버퍼를 직접 읽게 하면 본 루프와 소비 경합이 난다)
                if ctx.calCollecting {
                    ctx.calLock.lock()
                    if ctx.calCollecting {
                        ctx.calMic += accumMic.prefix(frameSize)
                        ctx.calRef += accumRef.prefix(min(frameSize, accumRef.count))
                        let cap = 48000 * 4
                        if ctx.calMic.count > cap { ctx.calMic.removeFirst(ctx.calMic.count - cap) }
                        if ctx.calRef.count > cap { ctx.calRef.removeFirst(ctx.calRef.count - cap) }
                    }
                    ctx.calLock.unlock()
                }
                var refSilent = true
                for i in 0..<frameSize {
                    let m = accumMic[i]
                    let r = i < accumRef.count ? accumRef[i] : 0
                    if bypass || st == nil {
                        outFrame[i] = m
                    } else {
                        i16Mic[i] = Int16(max(-32768, min(32767, Int32(m * 32767.0))))
                        i16Ref[i] = Int16(max(-32768, min(32767, Int32(r * 32767.0))))
                    }
                    if abs(r) > 1e-5 { refSilent = false }
                }
                accumMic.removeFirst(frameSize)
                accumRef.removeFirst(min(frameSize, accumRef.count))
                if !bypass, let es = st, let ps = pre {
                    speex_echo_cancellation(es, i16Mic, i16Ref, &i16Out)
                    _ = speex_preprocess_run(ps, &i16Out)
                    for i in 0..<frameSize {
                        outFrame[i] = Float32(i16Out[i]) / 32767.0
                    }
                }
                if refSilent { ctx.aecRefZeroFrames += 1 }
                ctx.ringOut.write(outFrame)
                ctx.aecFrames += 1
            }
            if accumMic.count < frameSize {
                // 마이크 한 프레임을 세마포어로 기다린다(타임아웃은 안전판).
                _ = ctx.wake.wait(timeout: .now() + 0.05)
            }
        }
        exitLock.lock()
        loopExited = true
        exitLock.unlock()
        exited.signal()
    }

    func stop() {
        running = false
        // 워커 루프가 실제로 빠져나올 때까지 기다린 뒤 상태를 파괴한다.
        // Thread.cancel()은 usleep 루프를 못 멈춘다(실측 크래시 원인).
        _ = exited.wait(timeout: .now() + 2.0)
        if let es = st { speex_echo_state_destroy(es) }
        if let ps = pre { speex_preprocess_state_destroy(ps) }
        st = nil; pre = nil
    }
}

// ---------- 인자 파싱 ----------

var mode = "aec"
var duration = 0.0
var recordPath = ""
var frameSizeArg = 480
var tailMsArg = 400
var listDevices = false
var farPath = ""
var autoCal = false
var esupArg = -40
var esupActiveArg = -15
let args = Array(CommandLine.arguments.dropFirst())
var ai = 0
while ai < args.count {
    let a = args[ai]
    switch a {
    case "--mode": ai += 1; if ai < args.count { mode = args[ai] }
    case "--duration": ai += 1; if ai < args.count { duration = Double(args[ai]) ?? 0 }
    case "--record": ai += 1; if ai < args.count { recordPath = args[ai] }
    case "--frame": ai += 1; if ai < args.count { frameSizeArg = Int(args[ai]) ?? 480 }
    case "--tail": ai += 1; if ai < args.count { tailMsArg = Int(args[ai]) ?? 400 }
    case "--refdelay": ai += 1; if ai < args.count { ctx.refDelaySamples = Int((Double(args[ai]) ?? 0) * 48.0) }
    case "--autocal": autoCal = true
    case "--esup": ai += 1; if ai < args.count { esupArg = Int(args[ai]) ?? -40 }
    case "--esup-active": ai += 1; if ai < args.count { esupActiveArg = Int(args[ai]) ?? -15 }
    case "--farfile": ai += 1; if ai < args.count { farPath = args[ai] }
    case "--devices": listDevices = true
    default: print("알 수 없는 인자: \(a)")
    }
    ai += 1
}

if listDevices {
    for id in allDeviceIDs() {
        print("[\(id)] \(deviceName(id) ?? "?")  uid=\(deviceUID(id) ?? "?") rate=\(Int(nominalRate(id)))")
    }
    exit(0)
}

ctx.mode = mode
guard mode == "aec" || mode == "bypass" else { fail("알 수 없는 모드: \(mode) (aec|bypass)") }

let micUID = "AppleUSBAudioEngine:ShenZhen Maono Technology Co., Ltd.:Maono Dynamic Microphone:SERIAL:1,2"
let spkUID = "DISPLAY-UID"
let bh2UID = "BlackHole2ch_UID"
let bh16UID = "BlackHole16ch_UID"

guard let micID = uidToID(micUID) else { fail("마이크(Maono)를 못 찾음") }
guard let spkID = uidToID(spkUID) else { fail("스피커(DELL)를 못 찾음") }
guard let bh2ID = uidToID(bh2UID) else { fail("BlackHole 2ch를 못 찾음") }
guard let bh16ID = uidToID(bh16UID) else { fail("BlackHole 16ch를 못 찾음") }

for (id, name) in [(micID, "mic"), (spkID, "spk"), (bh2ID, "bh2"), (bh16ID, "bh16")] {
    let st = setNominalRate(id, 48000)
    if st != noErr { print("WARN \(name) 48k 설정 실패 \(st) (현재 \(nominalRate(id)))") }
}

print("MODE=\(mode) duration=\(duration > 0 ? String(duration) : "until-CtrlC") frame=\(frameSizeArg) tail=\(tailMsArg)ms refdelay=\(ctx.refDelaySamples)smp(\(String(format: "%.0f", Double(ctx.refDelaySamples) / 48.0))ms)")
print("mic=\(deviceName(micID) ?? "?") rate=\(nominalRate(micID))")
print("spk=\(deviceName(spkID) ?? "?") rate=\(nominalRate(spkID))")
print("bh2=\(deviceName(bh2ID) ?? "?") rate=\(nominalRate(bh2ID))")
print("bh16=\(deviceName(bh16ID) ?? "?") rate=\(nominalRate(bh16ID))")

if !recordPath.isEmpty {
    FileManager.default.createFile(atPath: recordPath, contents: nil)
    guard let fh = FileHandle(forWritingAtPath: recordPath) else { fail("녹음 파일 열기 실패: \(recordPath)") }
    ctx.recordFile = fh
    print("녹음: \(recordPath) (f32le mono 48k)")
}

// farfile 로드 (측정 모드): f32le mono 48k 원시 PCM
if !farPath.isEmpty {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: farPath)), data.count % 4 == 0 else {
        fail("farfile 읽기 실패: \(farPath)")
    }
    ctx.farSamples = data.withUnsafeBytes { raw in
        Array(raw.bindMemory(to: Float32.self))
    }
    print("far samples=\(ctx.farSamples.count) (\(String(format: "%.1f", Double(ctx.farSamples.count) / 48000.0))s @48k)")
}

// ---------- 유닛 구성 ----------

var micUnit: AudioUnit? = nil
var spkUnit: AudioUnit? = nil
var bh16ProcID: AudioDeviceIOProcID? = nil
var bh2ProcID: AudioDeviceIOProcID? = nil

func teardown() {
    if let u = micUnit {
        AudioOutputUnitStop(u)
        AudioUnitUninitialize(u)
        AudioComponentInstanceDispose(u)
    }
    if let u = spkUnit {
        AudioOutputUnitStop(u)
        AudioUnitUninitialize(u)
        AudioComponentInstanceDispose(u)
    }
    if let p = bh2ProcID {
        AudioDeviceStop(bh2ID, p)
        AudioDeviceDestroyIOProcID(bh2ID, p)
    }
    if let p = bh16ProcID {
        AudioDeviceStop(bh16ID, p)
        AudioDeviceDestroyIOProcID(bh16ID, p)
    }
}

func makeUnit(subtype: UInt32) -> AudioUnit {
    var desc = AudioComponentDescription(
        componentType: kAudioUnitType_Output,
        componentSubType: OSType(subtype),
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0)
    guard let comp = AudioComponentFindNext(nil, &desc) else { fail("오디오 유닛 컴포넌트 없음 (subtype \(subtype))") }
    var u: AudioUnit? = nil
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

func configMicUnit(_ u: AudioUnit, device: AudioDeviceID) {
    var d = device
    must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &d, UInt32(MemoryLayout<AudioObjectID>.size)), "CurrentDevice(mic)")
    var enIn: UInt32 = 1
    must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enIn, 4), "EnableIO(mic input)")
    var enOut: UInt32 = 0
    must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enOut, 4), "EnableIO(mic output)")
    must(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fmt, fmtSize), "StreamFormat(mic)")
    var cb = AURenderCallbackStruct(inputProc: micInputProc, inputProcRefCon: nil)
    must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "SetInputCallback(mic)")
}

func configSpkUnit(_ u: AudioUnit, device: AudioDeviceID) {
    var d = device
    must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &d, UInt32(MemoryLayout<AudioObjectID>.size)), "CurrentDevice(spk)")
    var enIn: UInt32 = 0
    must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enIn, 4), "EnableIO(spk input)")
    var enOut: UInt32 = 1
    must(AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enOut, 4), "EnableIO(spk output)")
    must(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, fmtSize), "StreamFormat(spk)")
    var rc = AURenderCallbackStruct(inputProc: spkRenderProc, inputProcRefCon: nil)
    must(AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &rc, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "SetRenderCallback(spk)")
}

// ---------- 시작 ----------

let worker = SpeexAecWorker(frameSize: frameSizeArg, tailMs: tailMsArg, rate: 48000, bypass: mode == "bypass")
worker.autoCalibrate = autoCal
worker.echoSuppress = esupArg
worker.echoSuppressActive = esupActiveArg

must(AudioDeviceCreateIOProcID(bh16ID, bh16Proc, nil, &bh16ProcID), "BH16 IOProc")
must(AudioDeviceStart(bh16ID, bh16ProcID), "BH16 start")

must(AudioDeviceCreateIOProcID(bh2ID, bh2Proc, nil, &bh2ProcID), "BH2 IOProc")
must(AudioDeviceStart(bh2ID, bh2ProcID), "BH2 start")

let mu = makeUnit(subtype: kAudioUnitSubType_HALOutput)
configMicUnit(mu, device: micID)
must(AudioUnitInitialize(mu), "AudioUnitInitialize(mic)")
gMicUnit = mu
micUnit = mu
must(AudioOutputUnitStart(mu), "AudioOutputUnitStart(mic)")

let su = makeUnit(subtype: kAudioUnitSubType_HALOutput)
configSpkUnit(su, device: spkID)
must(AudioUnitInitialize(su), "AudioUnitInitialize(spk)")
spkUnit = su
must(AudioOutputUnitStart(su), "AudioOutputUnitStart(spk)")

worker.start()
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
        let (mp, mr, _) = ctx.micMeter.drain()
        let (rp, rr, _) = ctx.refMeter.drain()
        let (op, orr, _) = ctx.outMeter.drain()
        print(String(format: "[%3ds] mic %7.1f/%7.1f  ref %7.1f/%7.1f  out %7.1f/%7.1f  aecFrames=%d refZero=%d  underrun bh2=%d spk=%d  ring mic=%d ref=%d(%.0fms drop=%d) refSpk=%d(%.0fms drop=%d) out=%d  micCb=%d micFrames=%d(last=%d) micErr=%d spkCb=%d farW=%d",
                     tick, mp, mr, rp, rr, op, orr,
                     ctx.aecFrames, ctx.aecRefZeroFrames,
                     ctx.bh2Underruns, ctx.spkUnderruns,
                     ctx.ringMic.available,
                     ctx.ringRef.available, Double(ctx.ringRef.available) / 48.0, ctx.refDropped,
                     ctx.ringRefSpk.available, Double(ctx.ringRefSpk.available) / 48.0, gSpkDropped,
                     ctx.ringOut.available,
                     gMicCbCount, gMicTotalFrames, gMicLastCbFrames, gMicRenderErrCount, gSpkCbCount, gFarWriteFrames))
    }
}

_ = ctx.micMeter.drain(); _ = ctx.refMeter.drain(); _ = ctx.outMeter.drain()
if let fh = ctx.recordFile {
    ctx.recordLock.lock()
    try? fh.close()
    ctx.recordLock.unlock()
    print("녹음 종료: \(recordPath)")
}
let (mp, mr, mc) = ctx.micMeter.overall()
let (rp, rr, rc) = ctx.refMeter.overall()
let (op, orr, oc) = ctx.outMeter.overall()
print(String(format: "OVERALL mic  peak=%.1f rms=%.1f cb=%d", mp, mr, mc))
print(String(format: "OVERALL ref  peak=%.1f rms=%.1f cb=%d", rp, rr, rc))
print(String(format: "OVERALL out  peak=%.1f rms=%.1f cb=%d", op, orr, oc))
print("STATUS completed mode=\(mode)")

worker.stop()
teardown()
print("종료")
