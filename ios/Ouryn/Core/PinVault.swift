import Foundation
import Security
import CommonCrypto

// 앱 간편 비밀번호 (새로 정하면 4자리 · 예전에 정한 6자리는 바꿀 때까지 그대로)
// - 평소에는 앱을 여는 잠금. Face ID 등록이 바뀐 뒤에는 보내기 전에도 물음 (Biometry)
// - 1234·1111·1212 같은 뻔한 숫자는 새로 정할 수 없음 (weakReason)
// - Keychain 에 salt + PBKDF2 해시로만 저장 (숫자 그대로 저장하지 않음)
// - 틀린 횟수·마지막으로 틀린 시각도 같은 항목에 저장 → 앱을 껐다 켜도, 지웠다 다시 깔아도 초기화되지 않음
//   (iOS Keychain 은 앱을 지워도 남음. 복구 문구도 그래서 '이 폰에 있던 지갑 열기'가 가능함)
// - 5번까지는 그냥 다시 입력, 그 뒤로는 틀릴 때마다 기다리는 시간이 늘어남. 지갑을 지우지는 않음
//   기다리는 시간은 폰 시계와 부팅 뒤 흐른 시간(시계 설정과 무관) 중 짧은 쪽으로 셈 → 날짜를 앞으로 돌려도 줄지 않음
// - 10번 틀리면 hardLocked: 12단어(또는 등록이 그대로인 Face ID)로 확인할 때까지
//   비밀번호만으로는 보내기·복구 문구·비밀번호 바꾸기·지우기·바뀐 Face ID 받아들이기를 할 수 없음
//   새 비밀번호를 저장해도 이 잠금은 풀리지 않음 (clearHardLock 으로만 풂)

enum PinVault {
    private static let service = "com.yuanyx.ouryn.pin"
    private static let account = "app-pin"
    private static let rounds: UInt32 = 100_000
    static let freeTries = 5
    static let hardLockAfter = 10
    static let newLength = 4

    private struct Record: Codable {
        var salt: Data
        var hash: Data
        var fails = 0
        var lastFail: Date? = nil
        var length: Int? = nil   // 없으면 예전 6자리
        var locked: Bool? = nil  // hardLocked
        var lastFailMono: TimeInterval? = nil   // 마지막으로 틀린 때의 부팅 뒤 경과 시간 (잠자기 포함). 없으면 예전 기록
    }

    enum Check: Equatable {
        case ok
        case wrong(left: Int)        // 기다리지 않고 더 틀릴 수 있는 횟수
        case wait(TimeInterval)      // 이만큼 기다려야 다시 입력 가능
        case missing                 // 저장된 비밀번호 없음
    }

    static var exists: Bool { read() != nil }

    /// 지금 비밀번호의 자릿수 (확인 화면용). 없으면 새로 정할 자릿수
    static var length: Int { read().map { $0.length ?? 6 } ?? newLength }

    /// 10번 넘게 틀린 뒤 아직 새 비밀번호·12단어로 풀지 않음
    static var hardLocked: Bool { read()?.locked == true }

    /// 12단어(또는 등록이 그대로인 Face ID)로 본인 확인을 마쳤을 때만
    static func clearHardLock() {
        guard var r = read(), r.locked == true || r.fails > 0 else { return }
        r.locked = nil; r.fails = 0; r.lastFail = nil; r.lastFailMono = nil
        _ = write(r)
    }

    /// 새로 정하려는 비밀번호가 너무 뻔하면 이유, 괜찮으면 nil
    /// 같은 숫자 3개 연속 · 오름/내림 3개 연속 · ABAB · AABB · ABBA · 키패드 모양 → 4자리 1만 개 중 약 8%
    static func weakReason(_ pin: String) -> String? {
        let d = pin.compactMap(\.wholeNumberValue)
        guard d.count == newLength, d.count == pin.count else { return "숫자 \(newLength)자리를 입력해주세요" }
        for i in 0...(d.count - 3) {
            let a = d[i], b = d[i + 1], c = d[i + 2]
            if a == b && b == c { return "같은 숫자를 3번 연속 쓸 수 없어요" }
            if (b - a == 1 && c - b == 1) || (b - a == -1 && c - b == -1) { return "123, 987처럼 이어지는 숫자는 쓸 수 없어요" }
        }
        if (d[0] == d[2] && d[1] == d[3]) || (d[0] == d[1] && d[2] == d[3]) || (d[0] == d[3] && d[1] == d[2]) {
            return "1212, 1122, 1221처럼 반복되는 숫자는 쓸 수 없어요"
        }
        if keypadShapes.contains(pin) { return "키패드에서 한 줄로 누르는 숫자는 쓸 수 없어요" }
        return nil
    }

    /// 세로줄·대각선 (가로줄 123·456 등은 위의 이어지는 숫자에서 걸림)
    private static let keypadShapes: Set<String> = ["2580", "0852", "1470", "0741", "3690", "0963", "7410", "8520", "9630",
                                                     "1590", "0951", "3570", "0753", "1397", "7931"]

    /// 틀린 횟수에 따른 대기 시간 (초)
    static func delay(after fails: Int) -> TimeInterval {
        switch fails {
        case ..<freeTries: return 0
        case freeTries: return 30
        case freeTries + 1: return 60
        case freeTries + 2: return 5 * 60
        case freeTries + 3: return 15 * 60
        case freeTries + 4: return 60 * 60
        default: return 3 * 60 * 60
        }
    }

    /// 지금 기다려야 하는 시간 (없으면 nil)
    static var waitLeft: TimeInterval? { read().flatMap(waitLeft) }

    private static func waitLeft(_ r: Record) -> TimeInterval? {
        let d = delay(after: r.fails)
        guard d > 0, let last = r.lastFail else { return nil }
        let passed = elapsed(wall: Date().timeIntervalSince(last), mono: r.lastFailMono, nowMono: monotonicNow())
        let left = d - passed
        return left > 0 ? left : nil
    }

    /// 마지막으로 틀린 뒤 '확실히' 흐른 시간
    /// - wall: 폰 시계 기준 (음수면 시계를 되돌림). 사용자가 바꿀 수 있어서 이것만으로는 믿지 않음
    /// - mono: 틀린 때의 부팅 뒤 경과 시간. 지금 값이 더 작으면 그 사이 재부팅 → 부팅 뒤 흐른 시간만 확실함
    /// 둘 다 있으면 짧은 쪽 → 시계를 앞으로 돌려도 대기가 줄지 않음
    static func elapsed(wall: TimeInterval, mono: TimeInterval?, nowMono: TimeInterval) -> TimeInterval {
        guard let mono else { return max(0, wall) }   // 예전 기록: 시계를 되돌렸으면 처음부터 다시 기다림
        let sure = nowMono >= mono ? nowMono - mono : nowMono
        return wall < 0 ? sure : min(wall, sure)
    }

    /// 부팅 뒤 흐른 시간 (초). 폰이 잠자는 동안에도 늘고, 날짜·시간 설정을 바꿔도 변하지 않음
    static func monotonicNow() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    /// 비밀번호 확인. 틀리면 횟수를 Keychain 에 먼저 기록한 뒤 결과를 돌려줌
    static func check(_ pin: String) -> Check {
        guard var r = read() else { return .missing }
        if let w = waitLeft(r) { return .wait(w) }
        if let h = derive(pin, salt: r.salt), same(h, r.hash) {
            if r.fails != 0 { r.fails = 0; r.lastFail = nil; _ = write(r) }
            return .ok
        }
        r.fails += 1
        r.lastFail = Date()
        r.lastFailMono = monotonicNow()
        if r.fails >= hardLockAfter { r.locked = true }
        _ = write(r)
        if let w = waitLeft(r) { return .wait(w) }
        return .wrong(left: max(0, freeTries - r.fails))
    }

    /// 이미 본인 확인을 마친 흐름 안에서만: 새 비밀번호가 지금과 같은지 (횟수 기록 안 함)
    static func matchesCurrent(_ pin: String) -> Bool {
        guard let r = read(), let h = derive(pin, salt: r.salt) else { return false }
        return same(h, r.hash)
    }

    /// 새 비밀번호 저장 (틀린 횟수는 초기화)
    /// hardLocked 는 그대로 이어받음 — 비밀번호를 바꾸는 것만으로 10번 실패 잠금이 풀리지 않게. 풀려면 먼저 clearHardLock
    @discardableResult
    static func set(_ pin: String) -> Bool {
        var salt = Data(count: 16)
        let ok = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard ok == errSecSuccess, let h = derive(pin, salt: salt) else { return false }
        var record = Record(salt: salt, hash: h, length: pin.count)
        record.locked = read()?.locked == true ? true : nil
        return write(record)
    }

    @discardableResult
    static func delete() -> Bool {
        let s = SecItemDelete(query() as CFDictionary)
        return s == errSecSuccess || s == errSecItemNotFound
    }

    static func waitText(_ t: TimeInterval) -> String {
        let s = Int(ceil(t))
        if s < 60 { return "\(s)초" }
        let m = Int(ceil(Double(s) / 60))
        if m < 60 { return "\(m)분" }
        let h = m / 60, rest = m % 60
        return rest == 0 ? "\(h)시간" : "\(h)시간 \(rest)분"
    }

    // MARK: 내부

    private static func derive(_ pin: String, salt: Data) -> Data? {
        let pw: [CChar] = pin.utf8.map { CChar(bitPattern: $0) }
        var out = Data(count: 32)
        let status: Int32 = out.withUnsafeMutableBytes { (o: UnsafeMutableRawBufferPointer) -> Int32 in
            salt.withUnsafeBytes { (s: UnsafeRawBufferPointer) -> Int32 in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     pw, pw.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                     o.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        return Int(status) == kCCSuccess ? out : nil
    }

    /// 길이가 같으면 끝까지 비교 (일찍 끝나지 않게)
    private static func same(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[a.startIndex + i] ^ b[b.startIndex + i] }
        return diff == 0
    }

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() -> Record? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(Record.self, from: d)
    }

    private static func write(_ r: Record) -> Bool {
        guard let d = try? JSONEncoder().encode(r) else { return false }
        // 복구 문구와 같은 보호 수준: 이 폰에서만, 잠금 해제 상태에서만 읽힘. iCloud 키체인·백업 제외
        let attrs: [String: Any] = [kSecValueData as String: d,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let u = SecItemUpdate(query() as CFDictionary, attrs as CFDictionary)
        if u == errSecSuccess { return true }
        guard u == errSecItemNotFound else { return false }
        var q = query()
        q.merge(attrs) { _, n in n }
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

extension PinCheck {
    /// PinVault 결과 → 비밀번호 화면 메시지
    init(_ c: PinVault.Check) {
        switch c {
        case .ok: self = .ok
        case .wrong(let left):
            self = left <= 2
                ? .message(left == 0 ? "비밀번호가 맞지 않아요. 다음부터는 틀리면 잠시 기다려야 해요"
                                     : "비밀번호가 맞지 않아요 · \(left)번 더 틀리면 잠시 기다려야 해요")
                : .wrong
        case .wait(let t): self = .message("여러 번 틀렸어요. \(PinVault.waitText(t)) 뒤에 다시 시도해주세요")
        case .missing: self = .message("저장된 비밀번호를 찾지 못했어요. 복구 문구로 다시 열어주세요")
        }
    }
}
