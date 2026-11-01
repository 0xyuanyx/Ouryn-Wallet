import Foundation
@main struct Tests {
 static func main() throws {
  assert(WalletNetwork.allCases.count == 7)
  assert(WalletNetwork.mantle.chainID == 5000)
  assert(WalletNetwork.avalanche.chainID == 43114)
  assert(!WalletNetwork.tron.assets.contains("usdc"))
  let micro = try ExactAmount.parse("0.000001", decimals: 6); assert(micro == "1")
  let amount = try ExactAmount.parse("100.25", decimals: 6); assert(amount == "100250000")
  for invalid in ["-1", "1e3", "0.0000001", "NaN", "", "1..2"] {
   assert((try? ExactAmount.parse(invalid, decimals: 6)) == nil)
  }
  assert(ExactAmount.display(raw: "100250000", decimals: 6) == Decimal(string:"100.25")!)
  assert(ExactAmount.bytes("1000000000000000000")?.map { String(format:"%02x",$0) }.joined() == "0de0b6b3a7640000")
  print("PASS: seven networks, chain IDs, token support and exact amounts")
 }
}
