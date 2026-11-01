import Foundation

enum TronDraftValidator {
 static func valid(_ tx: [String:Any], owner:String, to:String, raw:String, contract:String?, parameter:String?, maxFee:Int64, now:Int64) -> Bool {
  guard let data = tx["raw_data"] as? [String:Any], let contracts = data["contract"] as? [[String:Any]], contracts.count == 1,
        let value = (contracts[0]["parameter"] as? [String:Any])?["value"] as? [String:Any],
        (value["owner_address"] as? String)?.lowercased() == owner.lowercased(),
        let expiry = data["expiration"] as? NSNumber, expiry.int64Value > now, expiry.int64Value <= now + 3600000,
        let timestamp = data["timestamp"] as? NSNumber, abs(timestamp.int64Value - now) < 300000,
        tx["txID"] as? String != nil, tx["raw_data_hex"] as? String != nil,
        (data["fee_limit"] as? NSNumber)?.int64Value ?? 0 <= maxFee else { return false }
  if let contract, let parameter {
   return contracts[0]["type"] as? String == "TriggerSmartContract"
    && (value["contract_address"] as? String)?.lowercased() == contract.lowercased()
    && (value["data"] as? String)?.lowercased() == "a9059cbb" + parameter.lowercased()
    && (value["call_value"] as? NSNumber)?.int64Value ?? 0 == 0
    && value["call_token_value"] == nil
  }
  return contracts[0]["type"] as? String == "TransferContract"
   && (value["to_address"] as? String)?.lowercased() == to.lowercased()
   && (value["amount"] as? NSNumber)?.stringValue == raw
 }
}
