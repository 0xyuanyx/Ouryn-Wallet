#!/usr/bin/env python3
"""Execute production scan transition methods with UI/storage boundaries replaced."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]/'Ouryn'
s=(root/'Screens/Receive.swift').read_text();scan=s[s.index('struct ScanView:'):s.index('// MARK: - 가까이 있는 사람에게')]
methods=scan[scan.index('    private func go('):scan.index('    private func checkCamera(')].replace('private func','func')
pay=(root/'Core/Pay.swift').read_text().split('// MARK: - 자산 이름')[0]
addr=(root/'Screens/People.swift').read_text().split('// MARK: - 거래 상세')[0].replace('import SwiftUI','')
code='''import SwiftUI
// Address-validation boundary: real checks are covered by the simulator WalletCore diagnostics.
enum WalletNetwork:String,CaseIterable { case solana = "솔라나" }
enum WalletKeys { static func valid(_ address:String,network:WalletNetwork) -> Bool { address == "11111111111111111111111111111111" || address == "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk" } }
let DOLLAR_NET = "솔라나"
func haptic(_ kind: Feedback) {}
enum Feedback { case success, error }
func noAnim(_ action: () -> Void) { action() }
enum ScanMotion { static let pulse = Animation.linear(duration: 0.45) }
struct Fixture { var myAddr = "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk" }
struct Store { var st = Fixture() }
@MainActor final class ScanHarness {
 enum Phase { case scan, lock, sheet, err }
 var store = Store()
 var active = true, picking = false, reduceMotion = false, frozen = false, flash = false, torch = false, readingPhoto = false
 var phase = Phase.scan
 var gen = 0, shake = 0
 var origin = CGPoint.zero
 var target: CGRect?
 var found: PayRequest?
 var pulse: CGFloat = 0
 var errText = ""
 var lastWarn = Date.distantPast
 var transitionTask: Task<Void,Never>?
 var photoTask: Task<Void,Never>?
'''+methods+'}\n'+pay+'\n'+addr+'''
@main struct Tests {
 @MainActor static func main() async throws {
  let other = "11111111111111111111111111111111"
  let request = "ouryn:" + other + "?a=12&t=t"
  let h = ScanHarness()
  h.handle(request, CGRect(x: 20,y: 30,width: 100,height: 100))
  assert(h.phase == .lock && h.frozen && h.found?.asset == "usdt" && h.found?.usd == 12)
  h.handle("garbage", nil)
  assert(h.phase == .lock, "Duplicate frame must not interrupt recognition")
  await h.transitionTask?.value
  assert(h.phase == .sheet)
  h.close(); assert(h.phase == .scan && !h.frozen && h.found == nil)
  h.handle(request,nil); h.invalidate(); h.active = false
  await h.transitionTask?.value
  assert(h.phase != .sheet, "Dismissed scan must not reveal a late result")
  h.close(); h.active = true; h.reduceMotion = true
  h.handle(request,nil); assert(h.phase == .sheet && !h.flash)
  h.close(); h.handle(h.store.st.myAddr,nil)
  assert(h.phase == .err && h.found == nil && h.shake == 0)
  await h.transitionTask?.value
  assert(h.phase == .scan)
  h.lastWarn = .distantPast; h.handle("https://example.org/private-data",nil)
  assert(h.phase == .err && !h.errText.contains("private-data"))
  h.invalidate()
  assert(parsePay("solana:" + other + "?amount=12&spl-token=unknown") == nil)
  print("PASS: recognition timing, duplicate frames, cancellation, retry, reduced motion, own/invalid QR, USDT amount retention")
 }
}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'scan.swift').write_text(code)
 subprocess.run(['swiftc','-module-cache-path','/tmp/ouryn-swift-cache','-parse-as-library',str(p/'scan.swift'),'-o',str(p/'scan')],check=True)
 subprocess.run([str(p/'scan')],check=True)
