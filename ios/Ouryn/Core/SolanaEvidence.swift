import Foundation

/// 서명된 솔라나 거래(레거시 메시지)를 다시 읽은 결과.
/// 서명기가 만든 바이트에 견적과 다른 지시(받는 곳, 수량, 토큰, 블록)가 들어가지 않았는지 보내기 전에 확인할 때 쓴다.
struct SolanaEvidence {
 struct Instruction: Equatable { let program: [UInt8]; let accounts: [[UInt8]]; let data: [UInt8] }
 enum Transfer {
  case sol(to: Data, lamports: UInt64)
  /// to = 받는 토큰 계정, wallet = 받는 지갑 주소. create면 받는 토큰 계정을 만드는 지시가 앞에 하나 더 있음
  case token(mint: Data, from: Data, to: Data, wallet: Data, amount: UInt64, decimals: UInt8, create: Bool)
 }
 enum Invalid: Error { case transaction }

 static let system = [UInt8](repeating: 0, count: 32) // 11111111111111111111111111111111
 static let tokenProgram = SolanaEvidence.bytes("06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9") // Tokenkeg…
 static let associatedProgram = SolanaEvidence.bytes("8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859") // ATokenGP…
 static let rent = SolanaEvidence.bytes("06a7d517192c5c51218cc94c3d4af17f58daee089ba1fd44e3dbd98a00000000") // SysvarRent…

 let signatures: [Data]
 /// 서명 대상 바이트 (서명들 뒤 전부)
 let message: Data
 let requiredSignatures: Int
 let keys: [[UInt8]]
 let blockhash: [UInt8]
 let instructions: [Instruction]

 /// 버전 있는 메시지(v0)나 남는 바이트는 거부.
 static func parse(_ raw: Data) throws -> SolanaEvidence {
  let b = [UInt8](raw)
  var i = 0
  func compact() throws -> Int {
   var value = 0
   for k in 0..<3 {
    guard i < b.count else { throw Invalid.transaction }
    let x = Int(b[i])
    i += 1
    value |= (x & 0x7f) << (7 * k)
    if x & 0x80 == 0 {
     guard k == 0 || x != 0, value <= 0xffff else { throw Invalid.transaction }
     return value
    }
   }
   throw Invalid.transaction
  }
  func take(_ n: Int) throws -> [UInt8] {
   guard i + n <= b.count else { throw Invalid.transaction }
   let out = Array(b[i..<i + n])
   i += n
   return out
  }
  let signatureCount = try compact()
  var signatures = [Data]()
  for _ in 0..<signatureCount {
   let s = try take(64)
   signatures.append(Data(s))
  }
  let start = i
  guard i < b.count, b[i] & 0x80 == 0 else { throw Invalid.transaction }
  let header = try take(3)
  let keyCount = try compact()
  var keys = [[UInt8]]()
  for _ in 0..<keyCount {
   let k = try take(32)
   keys.append(k)
  }
  let blockhash = try take(32)
  let instructionCount = try compact()
  var instructions = [Instruction]()
  for _ in 0..<instructionCount {
   let p = try take(1)
   guard Int(p[0]) < keys.count else { throw Invalid.transaction }
   let accountCount = try compact()
   let indices = try take(accountCount)
   guard indices.allSatisfy({ Int($0) < keys.count }) else { throw Invalid.transaction }
   let dataCount = try compact()
   let data = try take(dataCount)
   instructions.append(Instruction(program: keys[Int(p[0])], accounts: indices.map { keys[Int($0)] }, data: data))
  }
  guard i == b.count, signatureCount == Int(header[0]) else { throw Invalid.transaction }
  return SolanaEvidence(signatures: signatures, message: Data(b[start...]), requiredSignatures: Int(header[0]),
                        keys: keys, blockhash: blockhash, instructions: instructions)
 }

 /// 서명자는 보내는 사람 하나, 지시는 예상한 것만 정확히 (다른 지시가 하나라도 끼면 실패).
 func matches(owner: Data, blockhash hash: Data, transfer: Transfer) -> Bool {
  let o = [UInt8](owner)
  guard o.count == 32, signatures.count == 1, requiredSignatures == 1, keys.first == o, blockhash == [UInt8](hash) else { return false }
  switch transfer {
  case let .sol(to, lamports):
   let data: [UInt8] = Self.le(2, 4) + Self.le(lamports, 8) // System Transfer
   return instructions == [Instruction(program: Self.system, accounts: [o, [UInt8](to)], data: data)]
  case let .token(mint, from, to, wallet, amount, decimals, create):
   let m = [UInt8](mint), t = [UInt8](to)
   var data: [UInt8] = [12] // Token TransferChecked
   data += Self.le(amount, 8)
   data.append(decimals)
   let send = Instruction(program: Self.tokenProgram, accounts: [[UInt8](from), m, t, o], data: data)
   guard create else { return instructions == [send] }
   guard instructions.count == 2, instructions[1] == send else { return false }
   let make = instructions[0]
   let base: [[UInt8]] = [o, t, [UInt8](wallet), m, Self.system, Self.tokenProgram]
   return make.program == Self.associatedProgram && (make.accounts == base || make.accounts == base + [Self.rent])
    && make.data.count <= 1 && (make.data.first ?? 0) <= 1
  }
 }

 private static func le(_ v: UInt64, _ n: Int) -> [UInt8] {
  (0..<n).map { UInt8(truncatingIfNeeded: v >> (8 * UInt64($0))) }
 }

 private static func bytes(_ hex: String) -> [UInt8] {
  var out = [UInt8]()
  var i = hex.startIndex
  while i < hex.endIndex {
   let j = hex.index(i, offsetBy: 2)
   out.append(UInt8(hex[i..<j], radix: 16)!)
   i = j
  }
  return out
 }
}
