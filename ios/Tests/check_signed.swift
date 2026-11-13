import Foundation
import CryptoKit

// 서명 후 검증(EVMEvidence, SolanaEvidence) 검사.
// 아래 바이트는 Trust Wallet Core 4.8.3(앱과 같은 버전)이 공개 테스트 문구
// "abandon … about"으로 실제 서명한 결과다. 다시 만들려면 Tests/gen_signed_fixtures.mjs.
//
// 실행 (레포 루트):
//   swiftc -parse-as-library ios/Ouryn/Core/EVMEvidence.swift ios/Ouryn/Core/SolanaEvidence.swift ios/Tests/check_signed.swift -o /tmp/check_signed && /tmp/check_signed

func hex(_ s: String) -> Data {
 var out = [UInt8](); var i = s.startIndex
 while i < s.endIndex { let j = s.index(i, offsetBy: 2); out.append(UInt8(s[i..<j], radix: 16)!); i = j }
 return Data(out)
}
func num(_ n: UInt64) -> Data { Data(withUnsafeBytes(of: n.bigEndian) { Array($0) }) }
var failed = 0
func check(_ ok: Bool, _ name: String) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failed += 1 } }

@main struct Test {
 static func main() throws {
  // ── EVM
  let native = hex("f86c098504a817c800826270943535353535353535353535353535353535353535880de0b6b3a76400008026a03c5d032744ae6c81e79b0c91d67e6e96b52dc2fcc01802c0f51c44b4ebd8e498a018a1c6b97e5341dc18b425a712274ff87d7dd77bb41c3f0f5ab3d13a8d79319e")
  let to35 = EVMEvidence.address("0x3535353535353535353535353535353535353535")!
  let ev = try EVMEvidence.parse(native)
  let ether = hex("0de0b6b3a7640000")
  check(ev.matches(chainID: 1, nonce: num(9), gasPrice: num(20_000_000_000), gasLimit: num(25_200), contract: nil, recipient: to35, amount: ether), "EVM 기본 송금 일치")
  check(!ev.matches(chainID: 1, nonce: num(9), gasPrice: num(20_000_000_000), gasLimit: num(25_200), contract: nil, recipient: to35, amount: num(2)), "EVM 수량이 다르면 실패")
  check(!ev.matches(chainID: 5000, nonce: num(9), gasPrice: num(20_000_000_000), gasLimit: num(25_200), contract: nil, recipient: to35, amount: ether), "EVM 체인 번호가 다르면 실패")
  check(!ev.matches(chainID: 1, nonce: num(10), gasPrice: num(20_000_000_000), gasLimit: num(25_200), contract: nil, recipient: to35, amount: ether), "EVM nonce가 다르면 실패")
  check(!ev.matches(chainID: 1, nonce: num(9), gasPrice: num(20_000_000_000), gasLimit: num(30_000), contract: nil, recipient: to35, amount: ether), "EVM 가스 한도가 다르면 실패")
  check(!ev.matches(chainID: 1, nonce: num(9), gasPrice: num(20_000_000_000), gasLimit: num(25_200), contract: nil, recipient: Data(repeating: 0x36, count: 20), amount: ether), "EVM 받는 주소가 다르면 실패")

  let token = try EVMEvidence.parse(hex("f8ad808505d21dba00830130b0949702230a8ea53601f5cd2dc00fdbc13d4df4a8c780b844a9059cbb0000000000000000000000005322b34c88ed0691971bf52a7047448f0f4efc8400000000000000000000000000000000000000000000000000000000002625a0830150f7a01fcbc165d6e4891e030ef2c96b81639594a340fa04075b2ece1a47d9293178afa021e1e18d7a6713959fad089ff6983fab020c56dcd8d2a9a437878090d7143472"))
  let usdt = EVMEvidence.address("0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7")!
  let rcp = EVMEvidence.address("0x5322b34c88ed0691971bf52a7047448f0f4efc84")!
  check(token.matches(chainID: 43114, nonce: Data([0]), gasPrice: num(25_000_000_000), gasLimit: num(78_000), contract: usdt, recipient: rcp, amount: num(2_500_000)), "ERC-20 송금 일치 (Avalanche, nonce 0)")
  check(!token.matches(chainID: 43114, nonce: Data([0]), gasPrice: num(25_000_000_000), gasLimit: num(78_000), contract: usdt, recipient: to35, amount: num(2_500_000)), "ERC-20 받는 주소가 다르면 실패")
  check(!token.matches(chainID: 43114, nonce: Data([0]), gasPrice: num(25_000_000_000), gasLimit: num(78_000), contract: usdt, recipient: rcp, amount: num(2_500_001)), "ERC-20 수량이 다르면 실패")
  check(!token.matches(chainID: 43114, nonce: Data([0]), gasPrice: num(25_000_000_000), gasLimit: num(78_000), contract: nil, recipient: rcp, amount: num(2_500_000)), "ERC-20을 기본 송금으로 보면 실패")
  check(!token.matches(chainID: 43114, nonce: Data([0]), gasPrice: num(25_000_000_000), gasLimit: num(78_000), contract: to35, recipient: rcp, amount: num(2_500_000)), "ERC-20 토큰 컨트랙트가 다르면 실패")

  let mantle = try EVMEvidence.parse(hex("f86180018252089435353535353535353535353535353535353535350180822733a02f40c60ed6f4778bb9de8cf6ffcc20f2e6a9a49a71a114c5424be7357a968b44a067e653635a344060f4491fc2a20f86fd763b0af033492e2b8ac9f2aac52d6756"))
  check(mantle.matches(chainID: 5000, nonce: Data([0]), gasPrice: num(1), gasLimit: num(21_000), contract: nil, recipient: to35, amount: num(1)), "EVM 맨틀 체인 번호(5000)")
  check((try? EVMEvidence.parse(native + Data([0]))) == nil, "EVM 뒤에 남는 바이트 거부")
  check((try? EVMEvidence.parse(native.dropLast())) == nil, "EVM 잘린 거래 거부")
  check((try? EVMEvidence.parse(Data([2]) + native)) == nil, "EVM 타입 있는 거래 거부")
  check(EVMEvidence.address("0x12") == nil && EVMEvidence.address("0x" + String(repeating: "g", count: 40)) == nil, "EVM 주소 형식 검사")

  // ── 솔라나
  let owner = hex("f036276246a75b9de3349ed42b15e232f6518fc20f5fcd4f1d64e81f9bd258f7"), recipient = hex("c68b3c894c782b05a9c27fc6c66eb14d4e7d31de9086ab7d2129bcb0493afa02"), block = hex("43bd0c3a5052626bc1c7c8088ce543bd1b086e0f9909de99bd572e6d491b8e0b")
  let mint = hex("c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d61"), from = hex("40d2f27c461f29e9feba1ab8acd39496a9c65b0ae62a713f01f941a993bf55ed"), dest = hex("f3b5effd74b4795189160115a7bafa2b0a5130d699344de13fd8f81d5b39b923")
  let key = try CryptoKit.Curve25519.Signing.PublicKey(rawRepresentation: owner)

  let solRaw = hex("018fef7191a5bae2b540e06f48c892840b28de7013ba8c462dde30f9b2febfacb826301b4ea3987f3e2d59cf9577be490a03386a2ae8550be93563759520fed00801000103f036276246a75b9de3349ed42b15e232f6518fc20f5fcd4f1d64e81f9bd258f7c68b3c894c782b05a9c27fc6c66eb14d4e7d31de9086ab7d2129bcb0493afa02000000000000000000000000000000000000000000000000000000000000000043bd0c3a5052626bc1c7c8088ce543bd1b086e0f9909de99bd572e6d491b8e0b01020200010c0200000040420f0000000000")
  let sol = try SolanaEvidence.parse(solRaw)
  check(sol.matches(owner: owner, blockhash: block, transfer: .sol(to: recipient, lamports: 1_000_000)), "SOL 송금 일치")
  check(key.isValidSignature(sol.signatures[0], for: sol.message), "SOL 서명 확인")
  check(!sol.matches(owner: owner, blockhash: block, transfer: .sol(to: recipient, lamports: 1_000_001)), "SOL 수량이 다르면 실패")
  check(!sol.matches(owner: owner, blockhash: Data(repeating: 1, count: 32), transfer: .sol(to: recipient, lamports: 1_000_000)), "SOL 블록이 다르면 실패")
  check(!sol.matches(owner: recipient, blockhash: block, transfer: .sol(to: recipient, lamports: 1_000_000)), "SOL 보내는 사람이 다르면 실패")
  check(!sol.matches(owner: owner, blockhash: block, transfer: .sol(to: owner, lamports: 1_000_000)), "SOL 받는 주소가 다르면 실패")

  var tampered = [UInt8](solRaw); tampered[tampered.count - 6] ^= 1 // 수량 바이트 하나 바꿈
  let bad = try SolanaEvidence.parse(Data(tampered))
  check(!bad.matches(owner: owner, blockhash: block, transfer: .sol(to: recipient, lamports: 1_000_000)) && !key.isValidSignature(bad.signatures[0], for: bad.message), "SOL 바이트를 바꾸면 내용·서명 모두 실패")

  let tok = try SolanaEvidence.parse(hex("01b8a03d4ab2ada2389f7ca28bde5ba1e29e85a7c5a8bd528cea8ee4253a0f40f65794ed210baa5ac85680efdc12c9db64ad7d6280dc52bcf614c7b880ae42250101000205f036276246a75b9de3349ed42b15e232f6518fc20f5fcd4f1d64e81f9bd258f740d2f27c461f29e9feba1ab8acd39496a9c65b0ae62a713f01f941a993bf55edf3b5effd74b4795189160115a7bafa2b0a5130d699344de13fd8f81d5b39b923c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d6106ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a943bd0c3a5052626bc1c7c8088ce543bd1b086e0f9909de99bd572e6d491b8e0b010404010302000a0ca02526000000000006"))
  check(tok.matches(owner: owner, blockhash: block, transfer: .token(mint: mint, from: from, to: dest, wallet: recipient, amount: 2_500_000, decimals: 6, create: false)), "USDC 송금 일치")
  check(key.isValidSignature(tok.signatures[0], for: tok.message), "USDC 서명 확인")
  check(!tok.matches(owner: owner, blockhash: block, transfer: .token(mint: mint, from: from, to: from, wallet: recipient, amount: 2_500_000, decimals: 6, create: false)), "USDC 받는 토큰 계정이 다르면 실패")
  check(!tok.matches(owner: owner, blockhash: block, transfer: .token(mint: dest, from: from, to: dest, wallet: recipient, amount: 2_500_000, decimals: 6, create: false)), "USDC 토큰 종류가 다르면 실패")
  check(!tok.matches(owner: owner, blockhash: block, transfer: .token(mint: mint, from: from, to: dest, wallet: recipient, amount: 2_500_000, decimals: 6, create: true)), "계정 만들기 지시가 없는데 create면 실패")

  let make = try SolanaEvidence.parse(hex("012098401139f5c489a52d3eac2e4e361004917c7a37a783a6147d27a17250e2b6971f02f68dfde7405c0157f518f2bdf4ca79534ed0bec824b0682e06d625ac0f01000609f036276246a75b9de3349ed42b15e232f6518fc20f5fcd4f1d64e81f9bd258f7f3b5effd74b4795189160115a7bafa2b0a5130d699344de13fd8f81d5b39b92340d2f27c461f29e9feba1ab8acd39496a9c65b0ae62a713f01f941a993bf55edc68b3c894c782b05a9c27fc6c66eb14d4e7d31de9086ab7d2129bcb0493afa02c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d61000000000000000000000000000000000000000000000000000000000000000006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a906a7d517192c5c51218cc94c3d4af17f58daee089ba1fd44e3dbd98a000000008c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f85943bd0c3a5052626bc1c7c8088ce543bd1b086e0f9909de99bd572e6d491b8e0b02080700010304050607000604020401000a0ca02526000000000006"))
  check(make.matches(owner: owner, blockhash: block, transfer: .token(mint: mint, from: from, to: dest, wallet: recipient, amount: 2_500_000, decimals: 6, create: true)), "USDC 계정 만들기 + 송금 일치")
  check(key.isValidSignature(make.signatures[0], for: make.message), "USDC 계정 만들기 서명 확인")
  check(!make.matches(owner: owner, blockhash: block, transfer: .token(mint: mint, from: from, to: dest, wallet: owner, amount: 2_500_000, decimals: 6, create: true)), "계정 만들기의 받는 지갑이 다르면 실패")
  check(!make.matches(owner: owner, blockhash: block, transfer: .token(mint: mint, from: from, to: dest, wallet: recipient, amount: 2_500_000, decimals: 6, create: false)), "지시가 하나 더 있으면 실패")

  check((try? SolanaEvidence.parse(solRaw + Data([0]))) == nil, "SOL 뒤에 남는 바이트 거부")
  check((try? SolanaEvidence.parse(solRaw.dropLast())) == nil, "SOL 잘린 거래 거부")
  check((try? SolanaEvidence.parse(solRaw.prefix(65) + Data([0x80]) + solRaw.dropFirst(65))) == nil, "SOL 버전 있는 메시지 거부")

  print(failed == 0 ? "ALL PASS" : "\(failed) FAILED")
  if failed > 0 { exit(1) }
 }
}
