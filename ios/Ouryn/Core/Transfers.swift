import Foundation
import WalletCore

struct TransferQuote {
 let network: WalletNetwork
 let asset: String
 let owner: String
 let recipient: String
 let raw: String
 let fee: Decimal
 let expires: Date
 let draft: [String:Any]
 let parameter: String?
 let maxFee: Int64
}
struct PendingBroadcast: Codable, Equatable {
 let id:String
 let network:String
 let payload:Data
 let expires:Date?
 var lastAttempt:Date
 var validHeight:UInt64? = nil
 var validSlot:UInt64? = nil
 /// EVM: 보낸 주소와 서명에 쓴 nonce(10진수) — 같은 nonce 를 다른 거래가 쓰면 이 거래는 영영 확정될 수 없음
 var owner:String? = nil
 var nonce:String? = nil
 /// 비트코인: 이 거래가 쓰는 코인 "txid:vout" — 다른 거래가 먼저 쓰면 이 거래는 영영 확정될 수 없음
 var inputs:[String]? = nil
}

/// 이만큼 지나도 확정되지 않으면 '오래 걸리는 중'으로 표시하고 다시 보내는 간격을 늘림
enum PendingPolicy {
 static let staleAfter: TimeInterval = 72 * 60 * 60
 static func retryEvery(stale: Bool) -> TimeInterval { stale ? 10 * 60 : 30 }
}
struct SignedTransfer { let id: String; let payload: [String:Any] }
enum TransferError: LocalizedError {
 case invalid(String)
 var errorDescription: String? { switch self { case .invalid(let text): return text } }
}
enum TronTransfer {
 static var base: String { Testnet.on ? "https://nile.trongrid.io" : "https://api.trongrid.io" }
 static func quote(owner:String,to:String,asset:String,amount:String) async throws -> TransferQuote {
  guard ["trx","usdt"].contains(asset), WalletKeys.valid(to,network:.tron), owner != to else { throw TransferError.invalid("받는 트론 주소를 확인해주세요") }
  let raw = try ExactAmount.parse(amount,decimals:6)
  guard let value = Int64(raw), value > 0 else { throw TransferError.invalid("보낼 수량을 확인해주세요") }
  let balance = try await MultiChainAPI.tron(owner)
  guard Decimal(string:balance[asset] ?? "0")! >= Decimal(value) else { throw TransferError.invalid("선택한 코인의 잔액이 부족해요") }
  for address in [owner,to] {
   let account = try await MultiChainAPI.request(base + "/wallet/getaccount",body:["address":address,"visible":true])
   guard account["address"] != nil else { throw TransferError.invalid("트론 계정 활성화가 필요해요. 먼저 해당 주소로 TRX를 받아주세요") }
  }
  let chain = try await MultiChainAPI.request(base + "/wallet/getchainparameters",body:[:])
  guard let parameters = chain["chainParameter"] as? [[String:Any]],
        let energyCost = parameters.first(where:{ $0["key"] as? String == "getEnergyFee" })?["value"] as? NSNumber,
        let bandwidthCost = parameters.first(where:{ $0["key"] as? String == "getTransactionFee" })?["value"] as? NSNumber else { throw TransferError.invalid("현재 수수료를 확인하지 못했어요") }
  var maxFee = bandwidthCost.int64Value * 1000
  var parameter: String? = nil
  var draft: [String:Any]
  if asset == "usdt" {
   guard let hex = WalletKeys.tronHex(to) else { throw TransferError.invalid("주소를 확인해주세요") }
   let uint = String(value,radix:16)
   parameter = String(repeating:"0",count:24) + hex.suffix(40) + String(repeating:"0",count:64-uint.count) + uint
   let estimate = try await MultiChainAPI.request(base + "/wallet/triggerconstantcontract",body:["owner_address":owner,"contract_address":WalletNetwork.tron.contract(asset)!,"function_selector":"transfer(address,uint256)","parameter":parameter!,"visible":true])
   guard (estimate["result"] as? [String:Any])?["result"] as? Bool == true,
         let energy = estimate["energy_used"] as? NSNumber, energy.int64Value > 0, energy.int64Value < 1000000 else { throw TransferError.invalid("USDT 전송 예상 비용을 확인하지 못했어요") }
   maxFee += energy.int64Value * energyCost.int64Value * 13 / 10
   guard maxFee > 0, maxFee < 1000000000 else { throw TransferError.invalid("수수료 상한을 확인해주세요") }
   let result = try await MultiChainAPI.request(base + "/wallet/triggersmartcontract",body:["owner_address":owner,"contract_address":WalletNetwork.tron.contract(asset)!,"function_selector":"transfer(address,uint256)","parameter":parameter!,"fee_limit":maxFee,"visible":true])
   guard (result["result"] as? [String:Any])?["result"] as? Bool == true, let tx = result["transaction"] as? [String:Any] else { throw TransferError.invalid("전송 요청을 만들지 못했어요") }
   draft = tx
  } else {
   draft = try await MultiChainAPI.request(base + "/wallet/createtransaction",body:["owner_address":owner,"to_address":to,"amount":value,"visible":true])
  }
  let trx = Decimal(string:balance["trx"] ?? "0") ?? 0
  guard trx >= Decimal(maxFee) + (asset == "trx" ? Decimal(value) : 0) else { throw TransferError.invalid("수수료 상한을 충당할 TRX가 부족해요") }
  // API visible output addresses are normalized before validation and Wallet Core serialization.
  if var data = draft["raw_data"] as? [String:Any], var cs = data["contract"] as? [[String:Any]], cs.count == 1,
     var p = cs[0]["parameter"] as? [String:Any], var v = p["value"] as? [String:Any] {
   for field in ["owner_address","to_address","contract_address"] {
    if let address = v[field] as? String, address.hasPrefix("T"), let hex = WalletKeys.tronHex(address) { v[field] = hex }
   }
   p["value"] = v; cs[0]["parameter"] = p; data["contract"] = cs; draft["raw_data"] = data
  }
  guard let ownerHex = WalletKeys.tronHex(owner), let toHex = WalletKeys.tronHex(to),
    TronDraftValidator.valid(draft,owner:ownerHex,to:toHex,raw:raw,contract:asset == "usdt" ? WalletKeys.tronHex(WalletNetwork.tron.contract(asset)!) : nil,parameter:parameter,maxFee:maxFee,now:Int64(Date().timeIntervalSince1970*1000)) else { throw TransferError.invalid("전송 요청이 입력한 주소·수량과 달라요") }
  draft.removeValue(forKey:"visible")
  let block = try await MultiChainAPI.request(base + "/wallet/getnowblock",body:[:])
  guard let header = (block["block_header"] as? [String:Any])?["raw_data"] as? [String:Any] else { throw TransferError.invalid("최신 블록을 확인하지 못했어요") }
  draft["ouryn_block_header"] = header
  return TransferQuote(network:.tron,asset:asset,owner:owner,recipient:to,raw:raw,fee:Decimal(maxFee)/1000000,expires:Date().addingTimeInterval(45),draft:draft,parameter:parameter,maxFee:maxFee)
 }
 static func broadcast(_ signed: SignedTransfer) async throws {
  let result = try await MultiChainAPI.request(base + "/wallet/broadcasttransaction",body:signed.payload)
  guard result["result"] as? Bool == true else { throw TransferError.invalid("전파 응답을 확인하지 못했어요. 거래 해시로 확인 중이에요") }
 }
 static func status(_ hash: String) async throws -> TxStatus {
  let info = try await MultiChainAPI.request(base + "/walletsolidity/gettransactioninfobyid",body:["value":hash])
  guard info["blockNumber"] != nil else { return .pending }
  let receipt = info["receipt"] as? [String:Any]
  if let result = receipt?["result"] as? String, result != "SUCCESS" { return .failed }
  if info["result"] as? String == "FAILED" { return .failed }
  return .done
 }
}

enum TransferDispatcher {
 /// Failure is established only after the network's confirmed validity window ends.
 static func expired(_ pending:PendingBroadcast) async throws -> Bool {
  guard let network = WalletNetwork(rawValue:pending.network) else { return false }
  if network == .solana, let valid = pending.validHeight {
   let result = try await SolanaTransferEngine.rpc("getSignatureStatuses",[[pending.id],["searchTransactionHistory":true]]) as? [String:Any]
   guard let values = result?["value"] as? [Any], values.first is NSNull else { return false }
   let height = try await SolanaTransferEngine.rpc("getBlockHeight",[["commitment":"finalized"]]) as? NSNumber
   return (height?.uint64Value ?? 0) > valid
  }
  if network == .cardano, let valid = pending.validSlot {
   let rows = try await CardanoTransfer.query("/tx_status",body:["_tx_hashes":[pending.id]])
   guard rows.isEmpty || rows.first?["num_confirmations"] is NSNull else { return false }
   let tip = try await CardanoTransfer.query("/tip")
   return ((tip.first?["abs_slot"] as? NSNumber)?.uint64Value ?? 0) > valid + 300
  }
  if network.isEVM, let owner = pending.owner, let nonce = pending.nonce.flatMap({ Decimal(string:$0) }) {
   // 확정된 nonce 가 이 거래의 nonce 를 넘었는데 이 거래 영수증도, 거래 자체도 없으면 → 다른 거래로 교체됨
   let count = try await MultiChainAPI.rpc(network,"eth_getTransactionCount",[owner,"latest"])
   guard let used = ExactAmount.hexDecimal(count), used > nonce else { return false }
   guard try await EVMTransfer.status(pending.id,network:network) == .pending, let rpc = network.rpc else { return false }
   let found = try await MultiChainAPI.request(rpc,body:["jsonrpc":"2.0","id":1,"method":"eth_getTransactionByHash","params":[pending.id]])
   guard found["error"] == nil else { return false }
   return found["result"] == nil || found["result"] is NSNull
  }
  if network == .bitcoin, let inputs = pending.inputs, !inputs.isEmpty {
   // 쓰려던 코인을 다른 거래가 이미 썼으면 → 이 거래는 이중 사용이라 확정될 수 없음
   for input in inputs {
    let parts = input.split(separator:":")
    guard parts.count == 2 else { continue }
    let data = try await BitcoinTransfer.get("/tx/\(parts[0])/outspend/\(parts[1])")
    guard let spend = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { continue }
    if spend["spent"] as? Bool == true, let by = spend["txid"] as? String, by.lowercased() != pending.id.lowercased() { return true }
   }
   return false
  }
  if network == .tron, let expiration = pending.expires {
   let info = try await MultiChainAPI.request(TronTransfer.base + "/walletsolidity/gettransactionbyid",body:["value":pending.id])
   guard info.isEmpty else { return false }
   let block = try await MultiChainAPI.request(TronTransfer.base + "/walletsolidity/getnowblock",body:[:])
   let timestamp = (((block["block_header"] as? [String:Any])?["raw_data"] as? [String:Any])?["timestamp"] as? NSNumber)?.doubleValue ?? 0
   return timestamp / 1000 > expiration.timeIntervalSince1970 + 60
  }
  return false
 }
 static func broadcast(_ signed:SignedTransfer,network:WalletNetwork) async throws {
  switch network {
  case .tron: try await TronTransfer.broadcast(signed)
  case .solana: try await SolanaTransferEngine.broadcast(signed)
  case .bitcoin: try await BitcoinTransfer.broadcast(signed)
  case .cardano: try await CardanoTransfer.broadcast(signed)
  default: try await EVMTransfer.broadcast(signed,network:network)
  }
 }
}
