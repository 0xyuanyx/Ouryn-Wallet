#!/usr/bin/env python3
"""Execute production scan transition methods and the production QR parser with UI/storage boundaries replaced.

Needs swiftc (e.g. on the Mac). `python3 Tests/check_scan.py --print` prints the generated Swift instead of running it.

What is real (copied from the app source at run time):
- ScanView transition methods (Receive.swift)
- parsePay / ERC-681 / Solana Pay / Ouryn QR parsing (Pay.swift)
- WalletNetwork registry, token contracts and ExactAmount (Networks.swift)
- Testnet QR helpers (Testnet.swift, the "QR · 주소로 테스트넷 알아보기" section)
What is replaced: Wallet Core address validation (fixture addresses only), haptics, animation, the camera image.
"""
from pathlib import Path
import subprocess, sys, tempfile

root = Path(__file__).resolve().parents[1] / 'Ouryn'

s = (root / 'Screens/Receive.swift').read_text()
scan = s[s.index('struct ScanView:'):s.index('// MARK: - 가까이 있는 사람에게')]
methods = scan[scan.index('    private func go('):scan.index('    private func checkCamera(')].replace('private func', 'func')
pay = (root / 'Core/Pay.swift').read_text().split('// MARK: - 자산 이름')[0]
addr = (root / 'Screens/People.swift').read_text().split('// MARK: - 거래 상세')[0].replace('import SwiftUI', '')
networks = (root / 'Core/Networks.swift').read_text()
t = (root / 'Core/Testnet.swift').read_text()
testnet_qr = t[t.index('    // MARK: QR · 주소로 테스트넷 알아보기'):t.index('    // MARK: 주소 바꾸기')]

code = '''import SwiftUI
// Address-validation boundary: real checks are covered by the simulator WalletCore diagnostics.
let SOL_FIXTURES: Set<String> = ["11111111111111111111111111111111", "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk"]
enum WalletKeys {
 static func valid(_ address:String,network:WalletNetwork,test:Bool = Testnet.on) -> Bool {
  switch network {
  case .solana: return SOL_FIXTURES.contains(address)
  case .ethereum, .mantle, .avalanche:
   return address.count == 42 && address.hasPrefix("0x") && address.dropFirst(2).allSatisfy { $0.isHexDigit }
  default: return false
  }
 }
}
enum Testnet {
 static var on = false
''' + testnet_qr + '''}
let DOLLAR_NET = "솔라나"
func haptic(_ kind: Feedback) {}
enum Feedback { case success, error }
func noAnim(_ action: () -> Void) { action() }
enum ScanMotion {
 static let pulse = Animation.linear(duration: 0.45)
 static func ease(_ d: Double) -> Animation { .easeOut(duration: d) }
}
/// 카메라 사진 대역 (macOS 에는 UIImage 가 없음 · viewRect 는 크기만 씀)
struct StillImage { var size: CGSize }
struct Fixture { var myAddr = "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk" }
struct Store { var st = Fixture() }
@MainActor final class ScanHarness {
 enum Phase { case scan, lock, sheet, err }
 var store = Store()
 var active = true, picking = false, reduceMotion = false, frozen = false, flash = false, torch = false, readingPhoto = false
 var phase = Phase.scan
 var gen = 0, shake = 0
 var origin = CGPoint.zero
 var size = CGSize.zero
 var still: StillImage? = nil
 var launchFrom: CGRect? = nil
 var introDone = false
 var dismissed = false
 var target: CGRect?
 var found: PayRequest?
 var pulse: CGFloat = 0
 var errText = ""
 var lastWarn = Date.distantPast
 var transitionTask: Task<Void,Never>?
 var photoTask: Task<Void,Never>?
 func dismiss() { dismissed = true }
''' + methods + '}\n' + networks + '\n' + pay + '\n' + addr + '''
@main struct Tests {
 @MainActor static func main() async throws {
  let other = "11111111111111111111111111111111"
  let request = "ouryn:" + other + "?a=12&t=t"
  let h = ScanHarness()
  h.handle(request, CGRect(x: 20,y: 30,width: 100,height: 100))
  precondition(h.phase == .lock && h.frozen && h.found?.asset == "usdt" && h.found?.usd == 12)
  h.handle("garbage", nil)
  precondition(h.phase == .lock, "Duplicate frame must not interrupt recognition")
  await h.transitionTask?.value
  precondition(h.phase == .sheet)
  h.close(); precondition(h.phase == .scan && !h.frozen && h.found == nil)
  h.handle(request,nil); h.invalidate(); h.active = false
  await h.transitionTask?.value
  precondition(h.phase != .sheet, "Dismissed scan must not reveal a late result")
  h.close(); h.active = true; h.reduceMotion = true
  h.handle(request,nil); precondition(h.phase == .sheet && !h.flash)
  h.close(); h.handle(h.store.st.myAddr,nil)
  precondition(h.phase == .err && h.found == nil && h.shake == 0)
  await h.transitionTask?.value
  precondition(h.phase == .scan)
  h.lastWarn = .distantPast; h.handle("https://example.org/private-data",nil)
  precondition(h.phase == .err && !h.errText.contains("private-data"))
  h.invalidate()
  precondition(parsePay("solana:" + other + "?amount=12&spl-token=unknown") == nil)

  // ERC-681 (F01): 토큰 송금 요청은 받는 사람·토큰·수량을 그대로, 그 밖은 거부
  let usdc = "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
  let payee = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
  let erc20 = parsePay("ethereum:" + usdc + "@1/transfer?address=" + payee + "&uint256=1500000")
  precondition(erc20?.to == payee, "recipient must be the address parameter, not the token contract")
  precondition(erc20?.asset == "usdc" && erc20?.qty == "1.5" && erc20?.network == WalletNetwork.ethereum.rawValue && erc20?.mainnet == true)
  precondition(parsePay("ethereum:pay-" + usdc + "@1/transfer?address=" + payee + "&uint256=1e6")?.qty == "1")
  precondition(parsePay("ethereum:" + usdc + "@1/transfer?address=" + payee)?.qty == nil, "amount may be left to the user")
  precondition(parsePay("ethereum:" + usdc + "@1/approve?address=" + payee + "&uint256=1") == nil, "approve must be rejected")
  precondition(parsePay("ethereum:" + usdc + "/transfer?address=" + payee + "&uint256=1") == nil, "function call without chain id")
  precondition(parsePay("ethereum:" + payee + "@1/transfer?address=" + payee) == nil, "unknown token contract")
  precondition(parsePay("ethereum:" + usdc + "@1/transfer?address=" + usdc + "&uint256=1") == nil, "recipient equal to contract")
  precondition(parsePay("ethereum:" + usdc + "@43114/transfer?address=" + payee + "&uint256=1") == nil, "token contract of another chain")
  precondition(parsePay("ethereum:" + usdc + "@1/transfer?address=" + payee + "&uint256=1&uint256=2") == nil, "duplicate parameter")
  precondition(parsePay("ethereum:" + usdc + "@1/transfer?address=" + payee + "&uint256=1&foo=1") == nil, "unknown parameter")
  precondition(parsePay("ethereum:" + usdc + "@1/transfer?address=" + payee + "&uint256=0") == nil, "zero amount")
  precondition(parsePay("ethereum:" + payee + "@invalid") == nil, "invalid chain id")
  precondition(parsePay("ethereum:" + payee + "@999") == nil, "unknown chain id")
  precondition(parsePay("ethereum:" + payee + "@")  == nil, "empty chain id")
  precondition(parsePay("ethereum:" + payee)?.network == nil, "plain address keeps 0x ambiguity")
  precondition(parsePay("ethereum:" + payee + "@43114")?.network == WalletNetwork.avalanche.rawValue)
  precondition(parsePay("ethereum:" + payee + "@11155111")?.test == true, "Sepolia marks a testnet request")
  let native = parsePay("ethereum:" + payee + "@1?value=2.014e18")
  precondition(native?.asset == "eth" && native?.qty == "2.014" && native?.to == payee)
  precondition(parsePay("ethereum:" + payee + "?value=1") == nil, "amount without chain id")
  precondition(parsePay("ethereum:" + payee + "@1?value=0.5") == nil, "fractional wei")
  precondition(parsePay("ethereum:" + payee + "@1?value=-1") == nil, "negative amount")
  precondition(parsePay("ethereum:" + payee + "@1?data=0x00") == nil, "calldata parameter")
  precondition(parsePay("ethereum:" + payee + "@1?gas=21000")?.network == WalletNetwork.ethereum.rawValue, "fee hints do not change the meaning")

  // 정확 수량 변환
  precondition(ExactAmount.erc681("2.014e18") == "2014000000000000000")
  precondition(ExactAmount.erc681("1E6") == "1000000" && ExactAmount.erc681("100.0") == "100" && ExactAmount.erc681(".5e1") == "5")
  precondition(ExactAmount.erc681("1.") == nil && ExactAmount.erc681("1e") == nil && ExactAmount.erc681("0x10") == nil && ExactAmount.erc681("") == nil)
  precondition(ExactAmount.erc681("1e39") == nil, "more than 38 digits")
  precondition(ExactAmount.text(raw: "1500000", decimals: 6) == "1.5" && ExactAmount.text(raw: "5", decimals: 6) == "0.000005")
  precondition(ExactAmount.text(raw: "123", decimals: 0) == "123" && ExactAmount.text(raw: "0", decimals: 18) == "0")
  for raw in ["1", "1500000", "2014000000000000000", "999999999999999999"] {
   let back = try ExactAmount.parse(ExactAmount.text(raw: raw, decimals: 18)!, decimals: 18)
   precondition(back == raw, "text → parse roundtrip " + raw)
  }
  print("PASS: recognition timing, duplicate frames, cancellation, retry, reduced motion, own/invalid QR, USDT amount retention, ERC-681 meaning, exact amounts")
 }
}
'''

if '--print' in sys.argv:
    print(code)
    sys.exit(0)
with tempfile.TemporaryDirectory() as td:
    p = Path(td); (p / 'scan.swift').write_text(code)
    subprocess.run(['swiftc', '-module-cache-path', '/tmp/ouryn-swift-cache', '-parse-as-library', str(p / 'scan.swift'), '-o', str(p / 'scan')], check=True)
    subprocess.run([str(p / 'scan')], check=True)
