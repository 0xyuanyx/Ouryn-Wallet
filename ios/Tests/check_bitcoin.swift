import Foundation
@main struct Test {
 static func main() throws {
  let version = Data([1,0,0,0]); let input = Data([1]) + Data(repeating:0,count:36) + Data([0,255,255,255,255])
  let outputs = Data([1,232,3,0,0,0,0,0,0,1,81]); let lock = Data(repeating:0,count:4)
  let legacy = version + input + outputs + lock
  let parsed = try BitcoinEvidence.parse(legacy)
  assert(parsed.preimage == legacy && parsed.outputs[0].value == 1000 && parsed.outputs[0].script == Data([81]))
  let witness = version + Data([0,1]) + input + outputs + Data([1,1,0]) + lock
  let parsedWitness = try BitcoinEvidence.parse(witness); assert(parsedWitness.preimage == legacy)
  assert((try? BitcoinEvidence.parse(legacy + Data([0]))) == nil)
  assert((try? BitcoinEvidence.parse(Data([1,0]))) == nil)
  print("PASS: Bitcoin outputs, witness-stripped hash preimage and malformed data")
 }
}
