import Foundation

struct BitcoinEvidence {
 struct Output { let value: UInt64; let script: Data }
 let preimage: Data
 let outputs: [Output]
 enum Invalid: Error { case transaction }
 static func parse(_ data: Data) throws -> BitcoinEvidence {
  let bytes = [UInt8](data); var cursor = 0
  func read(_ count: Int) throws -> Data {
   guard count >= 0, cursor + count <= bytes.count else { throw Invalid.transaction }
   defer { cursor += count }; return Data(bytes[cursor..<cursor+count])
  }
  func integer(_ count: Int) throws -> UInt64 {
   let v = try read(count); return v.enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset*8) }
  }
  func variable() throws -> UInt64 {
   let prefix = try integer(1)
   switch prefix { case 253: let n = try integer(2); guard n >= 253 else { throw Invalid.transaction }; return n
   case 254: let n = try integer(4); guard n > 65535 else { throw Invalid.transaction }; return n
   case 255: let n = try integer(8); guard n > UInt32.max else { throw Invalid.transaction }; return n
   default: return prefix }
  }
  let version = try read(4)
  guard cursor + 2 < bytes.count else { throw Invalid.transaction }
  let witness = bytes[cursor] == 0 && bytes[cursor+1] == 1
  if witness { _ = try read(2) }
  let start = cursor
  let count = try variable(); guard count > 0, count <= 10000 else { throw Invalid.transaction }
  for _ in 0..<count {
   _ = try read(36); let scriptSize = try variable(); guard scriptSize <= 100000 else { throw Invalid.transaction }; _ = try read(Int(scriptSize)); _ = try read(4)
  }
  let outputCount = try variable(); guard outputCount > 0, outputCount <= 10000 else { throw Invalid.transaction }
  var outputs = [Output](); var sum: UInt64 = 0
  for _ in 0..<outputCount {
   let value = try integer(8); guard value <= 2100000000000000, sum <= 2100000000000000 - value else { throw Invalid.transaction }; sum += value
   let length = try variable(); guard length <= 100000 else { throw Invalid.transaction }
   outputs.append(Output(value:value,script:try read(Int(length))))
  }
  let stripped = Data(bytes[start..<cursor])
  if witness {
   for _ in 0..<count {
    let stack = try variable(); guard stack <= 10000 else { throw Invalid.transaction }
    for _ in 0..<stack { let length = try variable(); guard length <= 100000 else { throw Invalid.transaction }; _ = try read(Int(length)) }
   }
  }
  let lock = try read(4); guard cursor == bytes.count else { throw Invalid.transaction }
  return BitcoinEvidence(preimage:version + stripped + lock,outputs:outputs)
 }
}
