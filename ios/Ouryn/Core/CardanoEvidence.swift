import Foundation

/// Decode transaction outputs from the exact CBOR body used for the transaction ID.
struct CardanoEvidence {
 struct Input:Hashable { let hash:Data; let index:UInt64 }
 struct Output { let address:Data; let coin:UInt64; let tokens:[String:UInt64] }
 let body:Data
 let outputs:[Output]
 let fee:UInt64?
 let inputs:[Input]
 enum Invalid:Error { case transaction }
 private indirect enum Value {
  case uint(UInt64), bytes(Data), array([Value]), map([(Value,Value)]), other
  var uint:UInt64? { if case .uint(let v) = self { return v }; return nil }
  var bytes:Data? { if case .bytes(let v) = self { return v }; return nil }
  var array:[Value]? { if case .array(let v) = self { return v }; return nil }
  var map:[(Value,Value)]? { if case .map(let v) = self { return v }; return nil }
  func field(_ key:UInt64)->Value? { map?.first { $0.0.uint == key }?.1 }
 }
 static func parse(_ data:Data) throws -> CardanoEvidence {
  let bytes = Array(data); var cursor = 0
  func read(_ count:Int) throws -> Data {
   guard count >= 0, count <= bytes.count-cursor else { throw Invalid.transaction }
   defer { cursor += count }; return Data(bytes[cursor..<cursor+count])
  }
  func header() throws -> (UInt8,UInt64?) {
   let byte = try read(1).first!, extra = byte & 31
   let value:UInt64?
   if extra < 24 { value = UInt64(extra) }
   else if extra <= 27 { value = try read(1 << Int(extra-24)).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } }
   else if extra == 31 { value = nil }
   else { throw Invalid.transaction }
   return (byte >> 5,value)
  }
  func decode(_ depth:Int = 0) throws -> Value {
   guard depth < 32 else { throw Invalid.transaction }
   let (kind,length) = try header()
   switch kind {
   case 0: guard let length else { throw Invalid.transaction }; return .uint(length)
   case 1: guard length != nil else { throw Invalid.transaction }; return .other
   case 2,3:
    if let length { guard length <= UInt64(bytes.count) else { throw Invalid.transaction }; let d = try read(Int(length)); return kind == 2 ? .bytes(d) : .other }
    var d = Data()
    while cursor < bytes.count && bytes[cursor] != 255 { let v = try decode(depth+1); guard let chunk = v.bytes else { throw Invalid.transaction }; d.append(chunk) }
    guard try read(1).first == 255 else { throw Invalid.transaction }; return .bytes(d)
   case 4,5:
    if let length { guard length <= 10000 else { throw Invalid.transaction } }
    var values:[Value] = []; var pairs:[(Value,Value)] = []; var count:UInt64 = 0
    while length.map({count < $0}) ?? (cursor < bytes.count && bytes[cursor] != 255) {
     let first = try decode(depth+1)
     if kind == 5 { pairs.append((first,try decode(depth+1))) } else { values.append(first) }
     count += 1; guard count <= 10000 else { throw Invalid.transaction }
    }
    if length == nil { guard try read(1).first == 255 else { throw Invalid.transaction } }
    return kind == 5 ? .map(pairs) : .array(values)
   case 6: guard length != nil else { throw Invalid.transaction }; return try decode(depth+1)
   case 7: guard length != nil else { throw Invalid.transaction }; return .other
   default: throw Invalid.transaction
   }
  }
  let (kind,count) = try header()
  guard kind == 4, let count, (2...4).contains(count) else { throw Invalid.transaction }
  let start = cursor, body = try decode(), end = cursor
  for _ in 1..<count { _ = try decode() }
  guard cursor == bytes.count, let rawOutputs = body.field(1)?.array else { throw Invalid.transaction }
  var outputs:[Output] = []
  for output in rawOutputs {
   let address:Data?, value:Value?
   if let fields = output.array, fields.count >= 2 { address = fields[0].bytes; value = fields[1] }
   else { address = output.field(0)?.bytes; value = output.field(1) }
   guard let address, let value else { throw Invalid.transaction }
   var coin:UInt64; var tokens:[String:UInt64] = [:]
   if let c = value.uint { coin = c }
   else {
    guard let pair = value.array, pair.count == 2, let c = pair[0].uint, let policies = pair[1].map else { throw Invalid.transaction }; coin = c
    for (policy,assets) in policies {
     guard let p = policy.bytes, let names = assets.map else { throw Invalid.transaction }
     for (name,quantity) in names {
      guard let n = name.bytes, let q = quantity.uint else { throw Invalid.transaction }
      let key = p.map { String(format:"%02x",$0) }.joined() + "." + n.map { String(format:"%02x",$0) }.joined()
      guard tokens[key] == nil else { throw Invalid.transaction }; tokens[key] = q
     }
    }
   }
   outputs.append(Output(address:address,coin:coin,tokens:tokens))
  }
  var inputs:[Input] = []
  for entry in body.field(0)?.array ?? [] {
   guard let fields = entry.array, fields.count == 2, let hash = fields[0].bytes, hash.count == 32, let index = fields[1].uint else { throw Invalid.transaction }
   inputs.append(Input(hash:hash,index:index))
  }
  guard Set(inputs).count == inputs.count else { throw Invalid.transaction }
  return CardanoEvidence(body:data.subdata(in:start..<end),outputs:outputs,fee:body.field(2)?.uint,inputs:inputs)
 }
}
