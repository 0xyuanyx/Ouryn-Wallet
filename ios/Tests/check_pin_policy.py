#!/usr/bin/env python3
"""Run the production PinVault (real PBKDF2, real check/set/clearHardLock) with Keychain and clocks replaced by memory.

Needs swiftc (e.g. on the Mac). `python3 Tests/check_pin_policy.py --print` prints the generated Swift instead.

Regression checks for the 2026-10 security review:
- F02: a hard lock (10 failures) survives a correct PIN and a PIN change; only clearHardLock lifts it
- F03: moving the wall clock forward does not end the wait; real (monotonic) time does
"""
from pathlib import Path
import subprocess, sys, tempfile

root = Path(__file__).resolve().parents[1] / 'Ouryn'
s = (root / 'Core/PinVault.swift').read_text()
vault = s[s.index('enum PinVault {'):s.index('\nextension PinCheck')]
start = vault.index('    private static func query() -> [String: Any] {')
end = vault.rindex('}')
vault = vault[:start] + '''    // Keychain 대역 (메모리)
    static var memory: Data? = nil
    private static func query() -> [String: Any] { [:] }
    private static func read() -> Record? { memory.flatMap { try? JSONDecoder().decode(Record.self, from: $0) } }
    private static func write(_ r: Record) -> Bool { memory = try? JSONEncoder().encode(r); return memory != nil }
''' + vault[end:]
for old, new in [
    ('let s = SecItemDelete(query() as CFDictionary)', 'memory = nil; let s = errSecSuccess'),
    ('TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000', 'Clock.mono'),
    ('Date()', 'Clock.now'),
]:
    assert old in vault, old
    vault = vault.replace(old, new)

code = '''import Foundation
import Security
import CommonCrypto

/// 시계 대역: now = 폰 시계(사용자가 바꿀 수 있음), mono = 부팅 뒤 경과 시간
enum Clock {
    static var now = Date(timeIntervalSince1970: 1_800_000_000)
    static var mono: TimeInterval = 1_000
}

''' + vault + '''

@main struct Run {
    static func advance(_ seconds: TimeInterval, wall: TimeInterval? = nil) {
        Clock.mono += seconds
        Clock.now = Clock.now.addingTimeInterval(wall ?? seconds)
    }

    static func main() {
        // 확실히 흐른 시간의 경계
        precondition(PinVault.elapsed(wall: 100, mono: nil, nowMono: 0) == 100)
        precondition(PinVault.elapsed(wall: -5, mono: nil, nowMono: 0) == 0, "legacy record: clock moved back restarts the wait")
        precondition(PinVault.elapsed(wall: 86_400, mono: 100, nowMono: 150) == 50, "clock moved forward")
        precondition(PinVault.elapsed(wall: -100, mono: 100, nowMono: 400) == 300, "clock moved back")
        precondition(PinVault.elapsed(wall: 5_000, mono: 1_000, nowMono: 50) == 50, "rebooted since the failure")

        // F02: 10번 실패 잠금은 맞는 비밀번호·비밀번호 바꾸기로 풀리지 않음
        precondition(PinVault.set("1357") && !PinVault.hardLocked)
        for _ in 0..<PinVault.hardLockAfter {
            advance(4 * 3_600)
            switch PinVault.check("0000") {
            case .ok, .missing: preconditionFailure("wrong PIN accepted")
            default: break
            }
        }
        precondition(PinVault.hardLocked, "10 failures must hard-lock")
        advance(4 * 3_600)
        precondition(PinVault.check("1357") == .ok && PinVault.hardLocked, "a correct PIN does not lift the hard lock")
        precondition(PinVault.set("2468") && PinVault.hardLocked, "changing the PIN must not lift the hard lock")
        precondition(PinVault.check("2468") == .ok)
        PinVault.clearHardLock()
        precondition(!PinVault.hardLocked)

        // F03: 날짜를 앞으로 돌려도 대기가 줄지 않음
        for _ in 0..<PinVault.freeTries { advance(4 * 3_600); _ = PinVault.check("0000") }
        guard case .wait = PinVault.check("2468") else { preconditionFailure("5 failures must wait") }
        advance(1, wall: 86_400)
        guard case .wait = PinVault.check("2468") else { preconditionFailure("moving the clock forward must not end the wait") }
        advance(31)
        precondition(PinVault.check("2468") == .ok, "the wait ends after real time passes")
        print("PASS: elapsed bounds, hard lock survives correct PIN and PIN change, wait ignores clock changes")
    }
}
'''

if '--print' in sys.argv:
    print(code)
    sys.exit(0)
with tempfile.TemporaryDirectory() as td:
    p = Path(td); (p / 'pin.swift').write_text(code)
    subprocess.run(['swiftc', '-module-cache-path', '/tmp/ouryn-swift-cache', '-parse-as-library', str(p / 'pin.swift'), '-o', str(p / 'pin')], check=True)
    subprocess.run([str(p / 'pin')], check=True)
