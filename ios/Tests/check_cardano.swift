import Foundation
@main struct Tests {
 static func main() throws {
  // tx=[body={1:[[address bytes, [coin, {policy:{name:qty}}]]]}, witnesses={}]
  let data = Data([0x82,0xa1,0x01,0x81,0x82,0x42,0x01,0x02,0x82,0x19,0x03,0xe8,0xa1,0x41,0xaa,0xa1,0x41,0xbb,0x05,0xa0])
  let evidence = try CardanoEvidence.parse(data)
  assert(evidence.outputs.count == 1)
  assert(evidence.outputs[0].address == Data([1,2]))
  assert(evidence.outputs[0].coin == 1000)
  assert(evidence.outputs[0].tokens["aa.bb"] == 5)
  assert(evidence.body == data.subdata(in:1..<19))
  do { _ = try CardanoEvidence.parse(data.dropLast()); assertionFailure("truncated CBOR accepted") } catch {}
  print("PASS: Cardano raw body and output conservation evidence")
 }
}
