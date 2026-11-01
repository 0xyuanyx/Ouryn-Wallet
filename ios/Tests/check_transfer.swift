import Foundation
@main struct Test {
 static func main() throws {
  let owner = "41" + String(repeating:"1",count:40)
  let to = "41" + String(repeating:"2",count:40)
  let value: [String:Any] = ["owner_address":owner,"to_address":to,"amount":1000000]
  let contract: [String:Any] = ["type":"TransferContract","parameter":["value":value]]
  let tx: [String:Any] = ["raw_data":["contract":[contract],"expiration":200000,"timestamp":100000],"txID":"hash","raw_data_hex":"00"]
  assert(TronDraftValidator.valid(tx,owner:owner,to:to,raw:"1000000",contract:nil,parameter:nil,maxFee:1000000,now:100000))
  assert(!TronDraftValidator.valid(tx,owner:owner,to:to,raw:"2000000",contract:nil,parameter:nil,maxFee:1000000,now:100000))
  assert(!TronDraftValidator.valid(tx,owner:to,to:to,raw:"1000000",contract:nil,parameter:nil,maxFee:1000000,now:100000))
  assert(!TronDraftValidator.valid(tx,owner:owner,to:to,raw:"1000000",contract:nil,parameter:nil,maxFee:1000000,now:300000))
  print("PASS: Tron draft recipient, owner, amount and expiration validation")
 }
}
