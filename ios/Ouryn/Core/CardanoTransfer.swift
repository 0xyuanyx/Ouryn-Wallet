import Foundation
import WalletCore

enum CardanoTransfer {
 static var base: String { Testnet.on ? "https://preprod.koios.rest/api/v1" : "https://api.koios.rest/api/v1" }
 /// 주소 원문 바이트 — 테스트넷(addr_test)은 직접 bech32 로 읽음
 static func addressData(_ a: String) -> Data? { Testnet.on ? Testnet.cardanoBytes(a) : AnyAddress(string:a,coin:.cardano)?.data }
 static func query(_ path:String,body:[String:Any]? = nil) async throws -> [[String:Any]] {
  var r = URLRequest(url:URL(string:base + path)!); r.timeoutInterval = 20
  if let body { r.httpMethod = "POST"; r.setValue("application/json",forHTTPHeaderField:"Content-Type"); r.httpBody = try JSONSerialization.data(withJSONObject:body) }
  let (data,response) = try await URLSession.shared.data(for:r)
  guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let rows = try JSONSerialization.jsonObject(with:data) as? [[String:Any]] else { throw TransferError.invalid("카르다노 서버 응답을 확인하지 못했어요") }; return rows
 }
 static func quote(owner:String,to:String,asset:String,amount:String) async throws -> TransferQuote {
  guard ["ada","night"].contains(asset), WalletKeys.valid(to,network:.cardano), to.hasPrefix(Testnet.on ? "addr_test1" : "addr1"), owner != to else { throw TransferError.invalid(Testnet.on ? "받는 카르다노 preprod 주소를 확인해주세요" : "받는 카르다노 메인넷 주소를 확인해주세요") }
  let raw = try ExactAmount.parse(amount,decimals:6)
  guard let quantity = UInt64(raw), quantity > 0 else { throw TransferError.invalid("보낼 수량을 확인해주세요") }
  let tips = try await query("/tip")
  guard let tip = tips.first, let slot = tip["abs_slot"] as? NSNumber, let epoch = tip["epoch_no"] as? Int else { throw TransferError.invalid("현재 블록을 확인하지 못했어요") }
  let protocols = try await query("/epoch_params?_epoch_no=\(epoch)")
  guard let parameters = protocols.first, let a = parameters["min_fee_a"] as? NSNumber, let b = parameters["min_fee_b"] as? NSNumber,
    let coins = parameters["coins_per_utxo_size"] as? String, let maxSize = parameters["max_tx_size"] as? NSNumber,
    a.uint64Value > 0, maxSize.uint64Value <= 32768 else { throw TransferError.invalid("현재 거래 규칙을 확인하지 못했어요") }
  let rows = try await query("/address_utxos",body:["_addresses":[owner],"_extended":true])
  guard !rows.isEmpty, rows.count <= 50 else { throw TransferError.invalid("사용할 입금이 없거나 너무 많아요") }
  let hashes = Array(Set(rows.compactMap { $0["tx_hash"] as? String }))
  let transactions = try await query("/tx_cbor",body:["_tx_hashes":hashes])
  var evidenceByHash:[String:CardanoEvidence] = [:]
  for tx in transactions {
   guard let hash = tx["tx_hash"] as? String, let cbor = tx["cbor"] as? String, let bytes = Data(hexString:cbor) else { throw TransferError.invalid("이전 거래 원문을 확인하지 못했어요") }
   let evidence = try CardanoEvidence.parse(bytes)
   guard Hash.blake2b(data:evidence.body,size:32).hexString == hash else { throw TransferError.invalid("이전 거래 해시가 달라요") }
   evidenceByHash[hash] = evidence
  }
  var input = CardanoSigningInput()
  for row in rows {
   guard row["address"] as? String == owner, let hash = row["tx_hash"] as? String, let hashData = Data(hexString:hash),
     let index = row["tx_index"] as? UInt64, let value = row["value"] as? String, let lovelace = UInt64(value), let tokens = row["asset_list"] as? [[String:Any]] else { throw TransferError.invalid("입금 구성 정보를 확인하지 못했어요") }
   guard let evidence = evidenceByHash[hash], index < evidence.outputs.count,
         let addressBytes = CardanoTransfer.addressData(owner) else { throw TransferError.invalid("이전 출력 검증에 실패했어요") }
   let output = evidence.outputs[Int(index)]
   var amounts:[String:UInt64] = [:]
   for token in tokens {
    guard let policy = token["policy_id"] as? String, let name = token["asset_name"] as? String, let raw = token["quantity"] as? String, let count = UInt64(raw), amounts[policy + "." + name] == nil else { throw TransferError.invalid("토큰 출력 검증에 실패했어요") }
    amounts[policy + "." + name] = count
   }
   guard output.address == addressBytes, output.coin == lovelace, output.tokens == amounts else { throw TransferError.invalid("입금 원문의 주소·수량과 서버 응답이 달라요") }
   var utxo = CardanoTxInput.with { $0.address = owner; $0.amount = lovelace; $0.outPoint.txHash = hashData; $0.outPoint.outputIndex = index }
   for token in tokens {
    guard let policy = token["policy_id"] as? String, let name = token["asset_name"] as? String, let count = token["quantity"] as? String, let bytes = ExactAmount.bytes(count) else { throw TransferError.invalid("토큰 수량을 확인하지 못했어요") }
    utxo.tokenAmount.append(CardanoTokenAmount.with { $0.policyID = policy; $0.assetNameHex = name; $0.amount = bytes })
   }
   input.utxos.append(utxo)
  }
  var bundle = CardanoTokenBundle()
  if asset == "night" {
   bundle.token = [CardanoTokenAmount.with { $0.policyID = ChainAPI.nightPolicy; $0.assetNameHex = ChainAPI.nightName; $0.amount = ExactAmount.bytes(raw)! }]
  }
  guard let minimumString = Cardano.outputMinAdaAmount(toAddress:to,tokenBundle:try bundle.serializedData(),coinsPerUtxoByte:coins), let minimum = UInt64(minimumString) else { throw TransferError.invalid("최소 ADA 금액을 계산하지 못했어요") }
  let adaAmount = asset == "ada" ? quantity : minimum
  guard adaAmount >= minimum else { throw TransferError.invalid("받는 출력의 최소 ADA 금액보다 작아요") }
  input.ttl = slot.uint64Value + 1800
  input.transferMessage = CardanoTransferMessage.with { $0.toAddress = to; $0.changeAddress = owner; $0.amount = adaAmount; $0.tokenAmount = bundle }
  // Bound the exact fee by the protocol's maximum transaction size. The signer uses the actual encoded size.
  let cap = a.uint64Value * maxSize.uint64Value + b.uint64Value
  input.transferMessage.forceFee = cap
  let plan:CardanoTransactionPlan = AnySigner.plan(input:input,coin:.cardano)
  guard plan.error == .ok, plan.amount == adaAmount, plan.availableAmount >= adaAmount + cap else { throw TransferError.invalid("보낼 잔액 또는 수수료용 ADA가 부족해요") }
  let draft: [String:Any] = ["validSlot":input.ttl,"input":try input.serializedData().base64EncodedString(),"coefficient":a.uint64Value,"constant":b.uint64Value,"coinsPerByte":coins,"maximumSize":maxSize.uint64Value,"accompanyingADA":String(adaAmount)]
  return TransferQuote(network:.cardano,asset:asset,owner:owner,recipient:to,raw:raw,fee:Decimal(cap)/1000000,expires:Date().addingTimeInterval(45),draft:draft,parameter:nil,maxFee:Int64(cap))
 }
 static func broadcast(_ signed:SignedTransfer) async throws {
  guard let encoded = signed.payload["encoded"] as? String, let cbor = Data(hexString:encoded) else { throw TransferError.invalid("전송 데이터가 없어요") }
  var r = URLRequest(url:URL(string:base + "/submittx")!); r.httpMethod = "POST"; r.setValue("application/cbor",forHTTPHeaderField:"Content-Type"); r.httpBody = cbor
  let (data,response) = try await URLSession.shared.data(for:r)
  guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw TransferError.invalid("전파 응답을 확인하지 못했어요") }
  let id = String(data:data,encoding:.utf8)?.trimmingCharacters(in:CharacterSet(charactersIn:"\"\n "))
  guard id == signed.id else { throw TransferError.invalid("전송 해시 응답이 달라요") }
 }
 static func status(_ hash:String) async throws -> TxStatus {
  let rows = try await query("/tx_status",body:["_tx_hashes":[hash]])
  guard let row = rows.first, let confirmations = row["num_confirmations"] as? Int else { return .pending }
  return confirmations >= 3 ? .done : .pending
 }
}
// Avoid the adapter name colliding with WalletCore's CardanoTransfer alias.
typealias CardanoTransferMessage = WalletCore.CardanoTransfer
extension WalletKeys {
 static func signCardano(_ quote:TransferQuote) throws -> SignedTransfer {
  guard quote.network == .cardano, quote.expires > Date(), let wallet = signingWallet(), WalletKeys.signingAddress(wallet,.cardano) == quote.owner,
    let encoded = quote.draft["input"] as? String, let data = Data(base64Encoded:encoded), let ada = quote.draft["accompanyingADA"] as? String, let adaAmount = UInt64(ada),
    let a = quote.draft["coefficient"] as? UInt64, let b = quote.draft["constant"] as? UInt64, let maxSize = quote.draft["maximumSize"] as? UInt64,
    let coins = quote.draft["coinsPerByte"] as? String else { throw TransferError.invalid("전송 확인이 만료됐어요") }
  var input = try CardanoSigningInput(serializedData:data)
  guard input.transferMessage.toAddress == quote.recipient, input.transferMessage.changeAddress == quote.owner, input.transferMessage.amount == adaAmount, input.privateKey.isEmpty else { throw TransferError.invalid("전송 내용이 달라요") }
  input.privateKey = [WalletKeys.signingKey(wallet,.cardano).data]
  var fee = UInt64(quote.maxFee)
  for _ in 0..<5 {
   input.transferMessage.forceFee = fee
   input.plan = AnySigner.plan(input:input,coin:.cardano)
   guard input.plan.error == .ok else { throw TransferError.invalid("거래 구성에 실패했어요") }
   let changeBundle = CardanoTokenBundle.with { $0.token = input.plan.changeTokens }
   if input.plan.change > 0 {
    guard let minimum = Cardano.outputMinAdaAmount(toAddress:quote.owner,tokenBundle:try changeBundle.serializedData(),coinsPerUtxoByte:coins), let n = UInt64(minimum), input.plan.change >= n else { throw TransferError.invalid("남은 ADA가 잔돈의 최소 금액보다 작아요") }
   }
   let output:CardanoSigningOutput = AnySigner.sign(input:input,coin:.cardano)
   guard output.error == .ok, output.encoded.count <= maxSize else { throw TransferError.invalid("서명 검증에 실패했어요") }
   let required = a * UInt64(output.encoded.count) + b
   guard required <= UInt64(quote.maxFee) else { throw TransferError.invalid("실제 수수료가 확인한 상한을 넘어요") }
   if required == fee {
    let evidence = try CardanoEvidence.parse(output.encoded)
    guard evidence.fee == fee, Hash.blake2b(data:evidence.body,size:32) == output.txID,
          let recipient = CardanoTransfer.addressData(quote.recipient),
          let owner = CardanoTransfer.addressData(quote.owner) else { throw TransferError.invalid("서명한 거래 해시·수수료 검증에 실패했어요") }
    let destination = evidence.outputs.filter { $0.address == recipient }
    guard destination.count == 1, destination[0].coin == adaAmount,
          evidence.outputs.allSatisfy({ $0.address == owner || $0.address == recipient }) else { throw TransferError.invalid("서명한 거래의 받는 주소·수량이 달라요") }
    let tokenKey = ChainAPI.nightPolicy + "." + ChainAPI.nightName
    let expected:[String:UInt64] = quote.asset == "night" ? [tokenKey:UInt64(quote.raw)!] : [:]
    guard destination[0].tokens == expected else { throw TransferError.invalid("보내는 토큰 수량이 달라요") }
    var totalInput:UInt64 = 0; var inputTokens:[String:UInt64] = [:]
    let selected = input.plan.utxos.map { CardanoEvidence.Input(hash:$0.outPoint.txHash,index:$0.outPoint.outputIndex) }
    guard Set(selected) == Set(evidence.inputs), selected.count == evidence.inputs.count else { throw TransferError.invalid("서명한 거래의 사용 입력이 달라요") }
    for utxo in input.plan.utxos {
     let sum = totalInput.addingReportingOverflow(utxo.amount); guard !sum.overflow else { throw TransferError.invalid("입금 수량이 너무 커요") }; totalInput = sum.partialValue
     for token in utxo.tokenAmount {
      let count = token.amount.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }, key = token.policyID + "." + token.assetNameHex
      let sum = (inputTokens[key] ?? 0).addingReportingOverflow(count); guard !sum.overflow else { throw TransferError.invalid("토큰 수량이 너무 커요") }; inputTokens[key] = sum.partialValue
     }
    }
    var totalOutput:UInt64 = fee; var outputTokens:[String:UInt64] = [:]
    for value in evidence.outputs {
     let sum = totalOutput.addingReportingOverflow(value.coin); guard !sum.overflow else { throw TransferError.invalid("출력 수량이 너무 커요") }; totalOutput = sum.partialValue
     for (key,count) in value.tokens { let sum = (outputTokens[key] ?? 0).addingReportingOverflow(count); guard !sum.overflow else { throw TransferError.invalid("토큰 출력 수량이 너무 커요") }; outputTokens[key] = sum.partialValue }
    }
    guard totalInput == totalOutput, inputTokens == outputTokens else { throw TransferError.invalid("입금·출금·잔돈·수수료 보존 검증에 실패했어요") }
    return SignedTransfer(id:output.txID.hexString,payload:["encoded":output.encoded.hexString])
   }
   fee = required
  }
  throw TransferError.invalid("정확한 수수료를 계산하지 못했어요")
 }
}
