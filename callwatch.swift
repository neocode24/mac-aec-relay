import CoreAudio
import Foundation

// callwatch — 통화 시작/종료를 감지해 speexrelay를 자동으로 켜고 끈다.
//
// 왜 필요한가:
//   FaceTime 출력/마이크를 BlackHole로 고정해두면 릴레이가 꺼져 있을 때
//   통화가 아예 안 된다. 그렇다고 릴레이를 상시 켜두면 통화가 아닌 모든
//   소리까지 릴레이를 거쳐 89ms 지연이 붙는다.
//   그래서 통화가 시작되는 순간에만 릴레이를 띄운다.
//
// 감지 방법:
//   avconferenced(전화/FaceTime 백엔드)는 상시 떠 있지만 통화가 아닐 때는
//   오디오 장치를 잡지 않는다. CoreAudio 프로세스 목록에서 그 프로세스의
//   입출력 활성 플래그를 폴링해 전이 시점을 잡는다.
//
// 사용법:
//   callwatch [--relay <경로>] [--args "<릴레이 인자>"] [--interval <초>]
//   기본 릴레이 경로는 이 실행 파일과 같은 디렉토리의 speexrelay.

setvbuf(stdout, nil, _IOLBF, 0)

let sys = AudioObjectID(kAudioObjectSystemObject)
let global = kAudioObjectPropertyScopeGlobal

// CoreAudio 프로세스 관련 셀렉터 (audiodiag.swift와 동일)
let selProcList: AudioObjectPropertySelector   = 0x70726373  // 'prcs'
let selProcPID: AudioObjectPropertySelector    = 0x70706964  // 'ppid'
let selProcBundle: AudioObjectPropertySelector = 0x70626e64  // 'pbnd'
let selProcRunIn: AudioObjectPropertySelector  = 0x70726931  // 'pri1'
let selProcRunOut: AudioObjectPropertySelector = 0x70726f31  // 'pro1'

func addr(_ sel: AudioObjectPropertySelector,
          _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func ids(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
    var a = addr(sel, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var out = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    var sz = size
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &out) == noErr else { return [] }
    return out
}

func u32(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
    var a = addr(sel)
    var v: UInt32 = 0
    var sz = UInt32(MemoryLayout<UInt32>.size)
    _ = AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &v)
    return v
}

func str(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
    var a = addr(sel)
    var cf: CFString = "" as CFString
    var sz = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &cf) == noErr else { return "" }
    return cf as String
}

/// 통화 백엔드가 오디오를 잡고 있는가.
func callActive() -> Bool {
    for p in ids(sys, selProcList) {
        let bundle = str(p, selProcBundle)
        // avconferenced는 번들 ID가 비어 있을 수 있어 둘 다 본다.
        let isCallBackend = bundle.contains("avconference")
            || bundle.contains("FaceTime")
            || bundle.contains("mobilephone")
        guard isCallBackend else { continue }
        if u32(p, selProcRunIn) != 0 || u32(p, selProcRunOut) != 0 { return true }
    }
    return false
}

// ---------- 인자 ----------

let selfDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath().deletingLastPathComponent()
var relayPath = selfDir.appendingPathComponent("speexrelay").path
var relayArgs = ["--mode", "aec", "--autocal"]
var interval: TimeInterval = 1.0

var i = 1
let av = CommandLine.arguments
while i < av.count {
    switch av[i] {
    case "--relay":    i += 1; if i < av.count { relayPath = av[i] }
    case "--args":     i += 1; if i < av.count { relayArgs = av[i].split(separator: " ").map(String.init) }
    case "--interval": i += 1; if i < av.count { interval = Double(av[i]) ?? 1.0 }
    default: break
    }
    i += 1
}

guard FileManager.default.isExecutableFile(atPath: relayPath) else {
    FileHandle.standardError.write("FATAL: 릴레이를 실행할 수 없다: \(relayPath)\n".data(using: .utf8)!)
    exit(1)
}

// ---------- 릴레이 수명 관리 ----------

var relay: Process? = nil
let logDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/mac-aec-relay")
try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

func stamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.string(from: Date())
}

func startRelay() {
    guard relay == nil else { return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: relayPath)
    p.arguments = relayArgs
    let logURL = logDir.appendingPathComponent("relay-\(Int(Date().timeIntervalSince1970)).log")
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
    if let fh = try? FileHandle(forWritingTo: logURL) {
        p.standardOutput = fh
        p.standardError = fh
    }
    do {
        try p.run()
        relay = p
        print("[\(stamp())] 통화 감지 -> 릴레이 시작 (pid \(p.processIdentifier)) log=\(logURL.lastPathComponent)")
    } catch {
        print("[\(stamp())] 릴레이 시작 실패: \(error)")
    }
}

func stopRelay() {
    guard let p = relay else { return }
    p.terminate()          // SIGTERM — 릴레이가 정리 후 종료한다
    let deadline = Date().addingTimeInterval(3)
    while p.isRunning && Date() < deadline { usleep(50_000) }
    if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    print("[\(stamp())] 통화 종료 -> 릴레이 정지")
    relay = nil
}

// 감시자가 죽어도 릴레이를 남기지 않는다
signal(SIGINT)  { _ in stopRelay(); exit(0) }
signal(SIGTERM) { _ in stopRelay(); exit(0) }
atexit { stopRelay() }

// ---------- 폴링 루프 ----------
//
// 채터링 방지: 시작은 즉시, 종료는 3회 연속 비활성일 때만.
// 통화 중 잠깐 장치를 놓는 순간에 릴레이가 내려가면 소리가 끊긴다.

print("[\(stamp())] callwatch 시작. relay=\(relayPath) args=\(relayArgs.joined(separator: " "))")
var inactiveStreak = 0
let inactiveNeeded = 3

while true {
    let active = callActive()
    if active {
        inactiveStreak = 0
        if relay == nil { startRelay() }
        // 릴레이가 예기치 않게 죽었으면 다시 띄운다
        if let p = relay, !p.isRunning {
            print("[\(stamp())] 릴레이가 죽었다 -> 재시작")
            relay = nil
            startRelay()
        }
    } else {
        if relay != nil {
            inactiveStreak += 1
            if inactiveStreak >= inactiveNeeded { stopRelay(); inactiveStreak = 0 }
        }
    }
    Thread.sleep(forTimeInterval: interval)
}
