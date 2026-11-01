import Foundation

enum WalletNetwork: String, Codable, CaseIterable, Identifiable {
 case tron = "트론", solana = "솔라나", ethereum = "이더리움", mantle = "맨틀", avalanche = "Avalanche C-Chain", bitcoin = "비트코인", cardano = "카르다노"
 var id: String { rawValue }
 var chainID: Int? {
  if Testnet.on { switch self { case .ethereum: return 11155111; case .mantle: return 5003; case .avalanche: return 43113; default: return nil } }
  switch self { case .ethereum: return 1; case .mantle: return 5000; case .avalanche: return 43114; default: return nil }
 }
 var native: String { switch self { case .tron: return "trx"; case .solana: return "sol"; case .ethereum: return "eth"; case .mantle: return "mnt"; case .avalanche: return "avax"; case .bitcoin: return "btc"; case .cardano: return "ada" } }
 var assets: [String] { switch self { case .tron: return ["usdt","trx"]; case .solana: return ["usdc","usdt","sol"]; case .ethereum, .avalanche: return ["usdc","usdt",native]; case .mantle: return ["mnt","usdt0"]; case .bitcoin: return ["btc"]; case .cardano: return ["ada","night"] } }
 var rpc: String? {
  if Testnet.on { switch self { case .ethereum: return "https://ethereum-sepolia-rpc.publicnode.com"; case .mantle: return "https://rpc.sepolia.mantle.xyz"; case .avalanche: return "https://api.avax-test.network/ext/bc/C/rpc"; default: return nil } }
  switch self { case .ethereum: return "https://ethereum-rpc.publicnode.com"; case .mantle: return "https://rpc.mantle.xyz"; case .avalanche: return "https://api.avax.network/ext/bc/C/rpc"; default: return nil } }
 func contract(_ asset: String) -> String? {
  if Testnet.on {
   switch (self,asset) {
   case (.tron,"usdt"): return "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf" // Nile
   case (.ethereum,"usdc"): return "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" // Sepolia (Circle)
   case (.avalanche,"usdc"): return "0x5425890298aed601595a70AB815c96711a31Bc65" // Fuji (Circle)
   default: return nil
   }
  }
  switch (self,asset) {
  case (.mantle,"usdt0"): return "0x779Ded0c9e1022225f8E0630b35a9b54bE713736" // https://usdt0.to/ecosystem/mantle
  case (.tron,"usdt"): return "TR7NHqjeKQxGTCi8q8ZY4pL8otgjLj6t"
  case (.ethereum,"usdc"): return "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
  case (.ethereum,"usdt"): return "0xdAC17F958D2ee523a2206206994597C13D831ec7"
  case (.avalanche,"usdc"): return "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E"
  case (.avalanche,"usdt"): return "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7"
  default: return nil
  }
 }
 func decimals(_ asset: String) -> Int { if asset == "usdc" || asset == "usdt" || asset == "usdt0" || asset == "trx" || asset == "ada" || asset == "night" { return 6 }; if asset == "btc" { return 8 }; if asset == "sol" { return 9 }; return 18 }
}
enum AmountError: Error { case invalid }
enum ExactAmount {
 static func parse(_ text: String, decimals: Int) throws -> String {
  guard (0...18).contains(decimals), !text.isEmpty else { throw AmountError.invalid }
  let parts = text.split(separator: ".", omittingEmptySubsequences: false)
  guard parts.count <= 2, !parts[0].isEmpty, parts.allSatisfy({ $0.allSatisfy { $0 >= "0" && $0 <= "9" } }) else { throw AmountError.invalid }
  let fraction = parts.count == 2 ? String(parts[1]) : ""
  guard fraction.count <= decimals else { throw AmountError.invalid }
  let raw = String(parts[0]) + fraction + String(repeating: "0", count: decimals - fraction.count)
  let stripped = String(raw.drop(while: { $0 == "0" }))
  guard stripped.count <= 38 else { throw AmountError.invalid }
  return stripped.isEmpty ? "0" : stripped
 }
 static func display(raw: String, decimals: Int) -> Decimal {
  guard let n = Decimal(string: raw, locale: Locale(identifier:"en_US_POSIX")) else { return 0 }
  return n / pow(Decimal(10), decimals)
 }
 static func bytes(_ raw: String) -> Data? {
  guard !raw.isEmpty, raw.allSatisfy({ $0 >= "0" && $0 <= "9" }), raw.count <= 38 else { return nil }
  var digits = raw.compactMap { $0.wholeNumberValue }; var out = [UInt8]()
  while digits.contains(where:{ $0 != 0 }) {
   var carry = 0; var quotient = [Int]()
   for digit in digits { let value = carry * 10 + digit; if !quotient.isEmpty || value / 256 > 0 { quotient.append(value/256) }; carry = value % 256 }
   out.append(UInt8(carry)); digits = quotient
  }
  return Data(out.isEmpty ? [0] : out.reversed())
 }
 static func hexDecimal(_ hex: String) -> Decimal? {
  var value = Decimal(0)
  let h = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
  guard !h.isEmpty else { return nil }
  for c in h { guard let digit = c.hexDigitValue else { return nil }; value = value * 16 + Decimal(digit) }
  return value.isNaN ? nil : value
 }
}

extension WalletNetwork {
 /// 주소 페이지 — 블록체인에 실제로 얼마 있는지 앱 밖에서 확인
 func explorer(address a:String) -> URL? {
  guard !a.isEmpty else { return nil }
  let t = Testnet.on
  switch self {
  case .tron: return URL(string:(t ? "https://nile.tronscan.org/#/address/" : "https://tronscan.org/#/address/") + a)
  case .solana: return URL(string:"https://solscan.io/account/" + a + (t ? "?cluster=devnet" : ""))
  case .ethereum: return URL(string:(t ? "https://sepolia.etherscan.io/address/" : "https://etherscan.io/address/") + a)
  case .mantle: return URL(string:(t ? "https://explorer.sepolia.mantle.xyz/address/" : "https://explorer.mantle.xyz/address/") + a)
  case .avalanche: return URL(string:(t ? "https://testnet.snowtrace.io/address/" : "https://subnets.avax.network/c-chain/address/") + a)
  case .bitcoin: return URL(string:(t ? "https://mempool.space/testnet4/address/" : "https://mempool.space/address/") + a)
  case .cardano: return URL(string:(t ? "https://preprod.cardanoscan.io/address/" : "https://cardanoscan.io/address/") + a)
  }
 }
 func explorer(_ hash:String) -> URL? {
  guard !hash.isEmpty else { return nil }
  let base:String
  if Testnet.on {
   switch self {
   case .tron: base = "https://nile.tronscan.org/#/transaction/"
   case .solana: return URL(string:"https://solscan.io/tx/" + hash + "?cluster=devnet")
   case .ethereum: base = "https://sepolia.etherscan.io/tx/"
   case .mantle: base = "https://explorer.sepolia.mantle.xyz/tx/"
   case .avalanche: base = "https://testnet.snowtrace.io/tx/"
   case .bitcoin: base = "https://mempool.space/testnet4/tx/"
   case .cardano: base = "https://preprod.cardanoscan.io/transaction/"
   }
   return URL(string:base + hash)
  }
  switch self {
  case .tron: base = "https://tronscan.org/#/transaction/"
  case .solana: base = "https://solscan.io/tx/"
  case .ethereum: base = "https://etherscan.io/tx/"
  case .mantle: base = "https://explorer.mantle.xyz/tx/"
  case .avalanche: base = "https://subnets.avax.network/c-chain/tx/"
  case .bitcoin: base = "https://mempool.space/tx/"
  case .cardano: base = "https://cardanoscan.io/transaction/"
  }
  return URL(string:base + hash)
 }
}
