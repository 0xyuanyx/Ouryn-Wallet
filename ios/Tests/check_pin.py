"""Run the production PinVault.weakReason against known weak/strong PINs (needs swiftc, e.g. on the Mac)."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
s = (root/'Ouryn/Core/PinVault.swift').read_text()
body = s.split('    static func weakReason(', 1)[1].split('    /// 틀린 횟수에 따른 대기 시간', 1)[0]
code = '''
enum PinVault {
    static let newLength = 4
    static func weakReason(''' + body + '''
}
@main struct Run {
    static func main() {
        for p in ["1234", "4321", "0000", "1112", "1212", "1122", "1221", "2580", "0852", "1590", "7890", "9012"] {
            precondition(PinVault.weakReason(p) != nil, "should block " + p)
        }
        for p in ["1004", "0520", "3816", "5297", "2468", "9031"] {
            precondition(PinVault.weakReason(p) == nil, "should allow " + p)
        }
        precondition(PinVault.weakReason("12345") != nil && PinVault.weakReason("12a4") != nil)
        let blocked = (0..<10000).filter { PinVault.weakReason(String(format: "%04d", $0)) != nil }.count
        precondition(blocked == 781, "expected 781 blocked, got \\(blocked)")
        print("PASS: weak PIN rules block 781 of 10000 (7.8%)")
    }
}
'''
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp)
    (p/'pin.swift').write_text('import Foundation\n' + code)
    subprocess.run(['swiftc', '-module-cache-path', '/tmp/ouryn-swift-cache', '-parse-as-library', str(p/'pin.swift'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test')], check=True)
