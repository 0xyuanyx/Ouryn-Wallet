import Foundation
import WalletCore

enum BitcoinTransfer {
 static var base: String { Testnet.on ? "https://mempool.space/testnet4/api" : "https://mempool.space/api" }
 static var providers: [String] { Testnet.on ? ["https://mempool.space/testnet4/api"] : ["https://mempool.space/api","https://blockstream.info/api"] }
 static func get(_ path:String) async throws -> Data {
  for provider in providers {
   do {
    let fees = provider.contains("blockstream") && path == "/v1/fees/recommended"
    var request = URLRequest(url:URL(string:provider + (fees ? "/fee-estimates" : path))!); request.timeoutInterval = 12
    let (data,response) = try await URLSession.shared.data(for:request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
    if fees {
     guard let estimates = try JSONSerialization.jsonObject(with:data) as? [String:Double], let rate = estimates["3"] ?? estimates["6"], rate.isFinite, rate > 0, rate <= 1000 else { continue }
     return try JSONSerialization.data(withJSONObject:["halfHourFee":Int(ceil(rate))])
    }
    return data
   } catch { continue }
  }
  throw TransferError.invalid("비트코인 서버에 연결하지 못했어요")
 }
 static func quote(owner:String,to:String,amount:String) async throws -> TransferQuote {
  guard WalletKeys.valid(to,network:.bitcoin), owner != to else { throw TransferError.invalid("받는 비트코인 주소를 확인해주세요") }
  let raw = try ExactAmount.parse(amount,decimals:8)
  guard let satoshis = Int64(raw), satoshis >= 546 else { throw TransferError.invalid("보낼 금액이 너무 작아요") }
  let genesis = try await get("/block-height/0")
  guard String(data:genesis,encoding:.utf8) == (Testnet.on ? Testnet.bitcoinGenesis : "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f") else { throw TransferError.invalid(Testnet.on ? "비트코인 testnet4 연결을 확인해주세요" : "비트코인 메인넷 연결을 확인해주세요") }
  guard let available = try JSONSerialization.jsonObject(with:await get("/address/" + owner + "/utxo")) as? [[String:Any]],
        let fees = try JSONSerialization.jsonObject(with:await get("/v1/fees/recommended")) as? [String:Any], let rate = fees["halfHourFee"] as? Int, (1...1000).contains(rate) else { throw TransferError.invalid("잔액과 수수료를 확인하지 못했어요") }
  // 테스트넷 tb1 주소는 같은 스크립트의 bc1 표기로 바꿔 Wallet Core 에 넘김
  let script = BitcoinScript.lockScriptForAddress(address:Testnet.btcCore(owner),coin:.bitcoin).data
  var utxos = [BitcoinUnspentTransaction]()
  for row in available.prefix(50) {
   guard (row["status"] as? [String:Any])?["confirmed"] as? Bool == true,
         let hash = row["txid"] as? String, let index = row["vout"] as? Int, let value = row["value"] as? Int64 else { continue }
   let hex = String(data:try await get("/tx/" + hash + "/hex"),encoding:.utf8) ?? ""
   guard let data = Data(hexString:hex) else { throw TransferError.invalid("이전 거래 검증에 실패했어요") }
   let evidence = try BitcoinEvidence.parse(data)
   guard Hash.sha256SHA256(data:evidence.preimage).reversed().map({ String(format:"%02x",$0) }).joined() == hash,
         index >= 0, index < evidence.outputs.count, evidence.outputs[index].value == UInt64(value), evidence.outputs[index].script == script,
         let hashData = Data(hexString:hash) else { throw TransferError.invalid("사용할 코인의 출처·수량 검증에 실패했어요") }
   utxos.append(BitcoinUnspentTransaction.with {
    $0.outPoint.hash = Data(hashData.reversed()); $0.outPoint.index = UInt32(index); $0.outPoint.sequence = UInt32.max
    $0.script = script; $0.amount = value
   })
  }
  guard !utxos.isEmpty else { throw TransferError.invalid("확인된 입금이 없어요") }
  var input = BitcoinSigningInput.with {
   $0.amount = satoshis; $0.byteFee = Int64(rate); $0.toAddress = Testnet.btcCore(to); $0.changeAddress = Testnet.btcCore(owner)
   $0.coinType = CoinType.bitcoin.rawValue; $0.hashType = BitcoinScript.hashTypeForCoin(coinType:.bitcoin); $0.utxo = utxos
  }
  let plan:BitcoinTransactionPlan = AnySigner.plan(input:input,coin:.bitcoin)
  guard plan.error == .ok, plan.amount == satoshis, plan.fee > 0, plan.fee < satoshis, plan.availableAmount >= plan.amount + plan.fee else { throw TransferError.invalid("잔액 또는 수수료를 확인해주세요") }
  input.plan = plan
  return TransferQuote(network:.bitcoin,asset:"btc",owner:owner,recipient:to,raw:raw,fee:Decimal(plan.fee)/100000000,expires:Date().addingTimeInterval(45),draft:["input":try input.serializedData().base64EncodedString()],parameter:nil,maxFee:plan.fee)
 }
 /// 서명할 때 실제로 쓴 코인 목록 "txid:vout" (미확정 거래가 교체됐는지 확인할 때 씀)
 static func spentInputs(_ quote:TransferQuote) -> [String]? {
  guard quote.network == .bitcoin, let encoded = quote.draft["input"] as? String, let data = Data(base64Encoded:encoded),
        let input = try? BitcoinSigningInput(serializedData:data), !input.plan.utxos.isEmpty else { return nil }
  return input.plan.utxos.map { Data($0.outPoint.hash.reversed()).hexString + ":" + String($0.outPoint.index) }
 }
 static func broadcast(_ signed:SignedTransfer) async throws {
  guard let encoded = signed.payload["encoded"] as? String else { throw TransferError.invalid("전송 데이터가 없어요") }
  for provider in providers {
   do {
    var r = URLRequest(url:URL(string:provider + "/tx")!); r.timeoutInterval = 12; r.httpMethod = "POST"; r.setValue("text/plain",forHTTPHeaderField:"Content-Type"); r.httpBody = Data(encoded.utf8)
    let (data,response) = try await URLSession.shared.data(for:r)
    if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), String(data:data,encoding:.utf8) == signed.id { return }
   } catch { continue }
  }
  throw TransferError.invalid("전파 응답을 확인하지 못했어요")
 }
 static func status(_ hash:String) async throws -> TxStatus {
  let json = try JSONSerialization.jsonObject(with:await get("/tx/" + hash + "/status")) as? [String:Any]
  return json?["confirmed"] as? Bool == true ? .done : .pending
 }
}
extension WalletKeys {
 static func signBitcoin(_ quote:TransferQuote) throws -> SignedTransfer {
  guard quote.network == .bitcoin, quote.expires > Date(), let wallet = signingWallet(), WalletKeys.signingAddress(wallet,.bitcoin) == quote.owner,
    let encoded = quote.draft["input"] as? String, let data = Data(base64Encoded:encoded), let amount = Int64(quote.raw) else { throw TransferError.invalid("전송 확인이 만료됐어요") }
  var input = try BitcoinSigningInput(serializedData:data)
  guard input.amount == amount, input.toAddress == Testnet.btcCore(quote.recipient), input.changeAddress == Testnet.btcCore(quote.owner),
        input.plan.fee == quote.maxFee, input.plan.amount == amount, input.privateKey.isEmpty else { throw TransferError.invalid("전송 내용 검증에 실패했어요") }
  input.privateKey = [WalletKeys.signingKey(wallet,.bitcoin).data]
  let output:BitcoinSigningOutput = AnySigner.sign(input:input,coin:.bitcoin)
  guard output.error == .ok else { throw TransferError.invalid("전송 서명에 실패했어요") }
  let evidence = try BitcoinEvidence.parse(output.encoded)
  let toScript = BitcoinScript.lockScriptForAddress(address:Testnet.btcCore(quote.recipient),coin:.bitcoin).data
  let changeScript = BitcoinScript.lockScriptForAddress(address:Testnet.btcCore(quote.owner),coin:.bitcoin).data
  guard evidence.outputs.count <= 2, evidence.outputs.filter({ $0.script == toScript }).reduce(UInt64(0),{ $0 + $1.value }) == UInt64(amount),
    evidence.outputs.allSatisfy({ $0.script == toScript || $0.script == changeScript }),
    input.plan.utxos.reduce(Int64(0),{ $0 + $1.amount }) - Int64(evidence.outputs.reduce(UInt64(0),{ $0 + $1.value })) == quote.maxFee else { throw TransferError.invalid("수신 주소 또는 수수료 검증에 실패했어요") }
  let id = Hash.sha256SHA256(data:evidence.preimage).reversed().map { String(format:"%02x",$0) }.joined()
  return SignedTransfer(id:id,payload:["encoded":output.encoded.hexString])
 }
}
