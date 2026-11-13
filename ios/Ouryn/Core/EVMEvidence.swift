import Foundation

/// 서명된 EVM 거래(레거시 + EIP-155)를 다시 읽은 결과.
/// 서명기가 만든 바이트가 견적과 같은지(받는 곳, 수량, 체인, nonce, 수수료) 보내기 전에 확인할 때 쓴다.
struct EVMEvidence {
 let nonce: [UInt8]
 let gasPrice: [UInt8]
 let gasLimit: [UInt8]
 let to: [UInt8]
 let value: [UInt8]
 let data: [UInt8]
 let chainID: UInt64
 enum Invalid: Error { case transaction }

 /// RLP [nonce, gasPrice, gasLimit, to, value, data, v, r, s] 만 받는다. 타입 있는 거래(0x01, 0x02 …)나 남는 바이트는 거부.
 static func parse(_ raw: Data) throws -> EVMEvidence {
  let b = [UInt8](raw)
  let top = try item(b, 0)
  guard top.list, top.end == b.count else { throw Invalid.transaction }
  var fields = [[UInt8]]()
  var i = top.start
  while i < top.end {
   let field = try item(b, i)
   guard !field.list else { throw Invalid.transaction }
   fields.append(Array(b[field.start..<field.end]))
   i = field.end
  }
  guard i == top.end, fields.count == 9 else { throw Invalid.transaction }
  // 숫자 칸은 앞에 0이 붙으면 안 됨 (표준 인코딩만)
  for k in [0, 1, 2, 4, 6, 7, 8] where fields[k].first == 0 { throw Invalid.transaction }
  guard fields[3].count == 20, fields[6].count <= 8,
        (1...32).contains(fields[7].count), (1...32).contains(fields[8].count) else { throw Invalid.transaction }
  let v = fields[6].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
  guard v >= 37 else { throw Invalid.transaction } // EIP-155: v = 체인 번호 × 2 + 35/36
  return EVMEvidence(nonce: fields[0], gasPrice: fields[1], gasLimit: fields[2], to: fields[3],
                     value: fields[4], data: fields[5], chainID: (v - 35) / 2)
 }

 /// 숫자는 빅엔디안 바이트로 받고 앞의 0은 무시하고 비교한다. contract가 있으면 ERC-20 transfer(recipient, amount).
 func matches(chainID: UInt64, nonce: Data, gasPrice: Data, gasLimit: Data, contract: Data?, recipient: Data, amount: Data) -> Bool {
  let amt = Self.trim(amount)
  guard self.chainID == chainID, self.nonce == Self.trim(nonce), self.gasPrice == Self.trim(gasPrice),
        self.gasLimit == Self.trim(gasLimit), recipient.count == 20, !amt.isEmpty, amt.count <= 32 else { return false }
  guard let contract else { return to == [UInt8](recipient) && value == amt && data.isEmpty }
  var call: [UInt8] = [0xa9, 0x05, 0x9c, 0xbb]
  call += [UInt8](repeating: 0, count: 12)
  call += [UInt8](recipient)
  call += [UInt8](repeating: 0, count: 32 - amt.count)
  call += amt
  return contract.count == 20 && to == [UInt8](contract) && value.isEmpty && data == call
 }

 /// "0x" + 40자리 16진수 → 20바이트
 static func address(_ text: String) -> Data? {
  let h = text.hasPrefix("0x") || text.hasPrefix("0X") ? text.dropFirst(2) : Substring(text)
  guard h.count == 40 else { return nil }
  var out = [UInt8]()
  var high: UInt8? = nil
  for c in h {
   guard let digit = c.hexDigitValue, digit < 16 else { return nil }
   if let x = high { out.append((x << 4) | UInt8(digit)); high = nil } else { high = UInt8(digit) }
  }
  return Data(out)
 }

 private static func trim(_ d: Data) -> [UInt8] { Array([UInt8](d).drop(while: { $0 == 0 })) }

 private struct Item { let list: Bool; let start: Int; let end: Int }

 private static func item(_ b: [UInt8], _ i: Int) throws -> Item {
  guard i < b.count else { throw Invalid.transaction }
  let p = Int(b[i])
  switch p {
  case 0..<0x80:
   return Item(list: false, start: i, end: i + 1)
  case 0x80...0xb7:
   let n = p - 0x80
   // 0x80보다 작은 한 바이트는 접두사 없이 써야 표준
   if n == 1, i + 1 < b.count, b[i + 1] < 0x80 { throw Invalid.transaction }
   return try span(b, false, i + 1, n)
  case 0xb8...0xbf:
   let ll = p - 0xb7
   let n = try length(b, i + 1, ll)
   return try span(b, false, i + 1 + ll, n)
  case 0xc0...0xf7:
   return try span(b, true, i + 1, p - 0xc0)
  default:
   let ll = p - 0xf7
   let n = try length(b, i + 1, ll)
   return try span(b, true, i + 1 + ll, n)
  }
 }

 private static func length(_ b: [UInt8], _ s: Int, _ ll: Int) throws -> Int {
  guard ll <= 4, s + ll <= b.count, b[s] != 0 else { throw Invalid.transaction }
  let n = b[s..<s + ll].reduce(0) { ($0 << 8) | Int($1) }
  guard n >= 56 else { throw Invalid.transaction }
  return n
 }

 private static func span(_ b: [UInt8], _ list: Bool, _ s: Int, _ n: Int) throws -> Item {
  guard s + n <= b.count else { throw Invalid.transaction }
  return Item(list: list, start: s, end: s + n)
 }
}
