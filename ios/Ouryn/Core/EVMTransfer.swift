import Foundation
import WalletCore

enum EVMTransfer {
 /// 공개 RPC 가 알려준 gas 가격의 상한 (1000 gwei). 넘으면 비정상 견적으로 보고 서명하지 않음
 static let maxGasPrice = Decimal(1_000_000_000_000)
 static func quote(network:WalletNetwork,owner:String,to:String,asset:String,amount:String) async throws -> TransferQuote {
  guard [.ethereum,.mantle,.avalanche].contains(network), network.assets.contains(asset), WalletKeys.valid(to,network:network), owner.lowercased() != to.lowercased() else { throw TransferError.invalid("자산과 받는 주소를 확인해주세요") }
  let raw = try ExactAmount.parse(amount,decimals:network.decimals(asset))
  guard let quantity = Decimal(string:raw), quantity > 0, let bytes = ExactAmount.bytes(raw) else { throw TransferError.invalid("보낼 수량을 확인해주세요") }
  let balances = try await MultiChainAPI.evm(owner,net:network)
  guard Decimal(string:balances[asset] ?? "0")! >= quantity else { throw TransferError.invalid("선택한 네트워크 잔액이 부족해요") }
  let nonce = try await MultiChainAPI.rpc(network,"eth_getTransactionCount",[owner,"pending"])
  let gasPrice = try await MultiChainAPI.rpc(network,"eth_gasPrice",[])
  let token = network.contract(asset)
  var call: [String:Any] = ["from":owner,"to":token ?? to,"value":token == nil ? "0x" + bytes.hexString : "0x0"]
  if token != nil {
   let valueHex = bytes.hexString
   call["data"] = "0xa9059cbb" + String(repeating:"0",count:24) + to.dropFirst(2).lowercased() + String(repeating:"0",count:64-valueHex.count) + valueHex
  }
  let estimated = try await MultiChainAPI.rpc(network,"eth_estimateGas",[call])
  guard let gas = ExactAmount.hexDecimal(estimated), gas >= 21000, gas <= (network == .mantle ? 100000000 : 1000000),
        let price = ExactAmount.hexDecimal(gasPrice), price > 0,
        let nonceValue = ExactAmount.hexDecimal(nonce), nonceValue >= 0 else { throw TransferError.invalid("수수료 견적을 확인하지 못했어요") }
  guard price <= maxGasPrice else { throw TransferError.invalid("네트워크 수수료가 비정상적으로 높아요. 잠시 뒤 다시 시도해주세요") }
  let limit = NSDecimalNumber(decimal:gas * Decimal(string:"1.2")!).uint64Value
  let feeRaw = Decimal(limit) * price
  let native = Decimal(string:balances[network.native] ?? "0") ?? 0
  guard native >= feeRaw + (token == nil ? quantity : 0) else { throw TransferError.invalid("수수료를 충당할 " + network.native.uppercased() + "가 부족해요") }
  let draft: [String:Any] = ["nonce":NSDecimalNumber(decimal:nonceValue).stringValue,"gasPrice":NSDecimalNumber(decimal:price).stringValue,"gasLimit":String(limit),"chainID":network.chainID!,"to":token ?? to]
  return TransferQuote(network:network,asset:asset,owner:owner,recipient:to,raw:raw,fee:feeRaw/pow(Decimal(10),18),expires:Date().addingTimeInterval(45),draft:draft,parameter:nil,maxFee:0)
 }
 static func broadcast(_ signed:SignedTransfer,network:WalletNetwork) async throws {
  guard let encoded = signed.payload["encoded"] as? String else { throw TransferError.invalid("전송 데이터가 없어요") }
  let hash = try await MultiChainAPI.rpc(network,"eth_sendRawTransaction",[encoded])
  guard hash.lowercased() == signed.id.lowercased() else { throw TransferError.invalid("전송 응답 해시가 달라요. 기존 거래를 확인 중이에요") }
 }
 /// 영수증이 생겨도 바로 '완료'로 보지 않고, 그 위에 블록이 충분히 쌓였을 때 완료 (network.confirmations)
 /// 그 전까지는 확인 중으로 두고 다음 동기화 때 다시 봄 → 짧은 재조직으로 사라진 거래를 완료로 남기지 않음
 static func status(_ hash:String,network:WalletNetwork) async throws -> TxStatus {
  guard let rpc = network.rpc else { throw TransferError.invalid("네트워크 오류") }
  let response = try await MultiChainAPI.request(rpc,body:["jsonrpc":"2.0","id":1,"method":"eth_getTransactionReceipt","params":[hash]])
  guard response["error"] == nil else { throw MultiChainAPI.APIError.invalid }
  guard let receipt = response["result"] as? [String:Any], let status = receipt["status"] as? String else { return .pending }
  guard status == "0x1" else { return .failed }
  guard network.confirmations > 1 else { return .done }
  guard let included = (receipt["blockNumber"] as? String).flatMap({ ExactAmount.hexDecimal($0) }),
        let head = ExactAmount.hexDecimal(try await MultiChainAPI.rpc(network,"eth_blockNumber",[])), head >= included else { return .pending }
  return head - included + 1 >= Decimal(network.confirmations) ? .done : .pending
 }
}
extension WalletKeys {
 static func signEVM(_ quote:TransferQuote) throws -> SignedTransfer {
  guard [.ethereum,.mantle,.avalanche].contains(quote.network), quote.expires > Date(),
        let wallet = signingWallet(), WalletKeys.signingAddress(wallet,.ethereum).lowercased() == quote.owner.lowercased(),
        quote.draft["chainID"] as? Int == quote.network.chainID,
        let nonce = quote.draft["nonce"] as? String, let nonceData = ExactAmount.bytes(nonce),
        let gasPrice = quote.draft["gasPrice"] as? String, let priceData = ExactAmount.bytes(gasPrice),
        let gasLimit = quote.draft["gasLimit"] as? String, let gasData = ExactAmount.bytes(gasLimit),
        let chainData = ExactAmount.bytes(String(quote.network.chainID!)), let amountData = ExactAmount.bytes(quote.raw)
  else { throw TransferError.invalid("확인이 만료됐거나 지갑을 열 수 없어요") }
  let input = EthereumSigningInput.with {
   $0.chainID = chainData; $0.nonce = nonceData; $0.gasPrice = priceData; $0.gasLimit = gasData
   $0.toAddress = quote.network.contract(quote.asset) ?? quote.recipient
   $0.privateKey = WalletKeys.signingKey(wallet,.ethereum).data
   $0.transaction = EthereumTransaction.with {
    if quote.network.contract(quote.asset) != nil {
     $0.erc20Transfer = EthereumTransaction.ERC20Transfer.with { $0.to = quote.recipient; $0.amount = amountData }
    } else { $0.transfer = EthereumTransaction.Transfer.with { $0.amount = amountData } }
   }
  }
  let output:EthereumSigningOutput = AnySigner.sign(input:input,coin:.ethereum)
  guard output.error == .ok, !output.encoded.isEmpty else { throw TransferError.invalid("서명 검증에 실패했어요") }
  let id = "0x" + Hash.keccak256(data:output.encoded).hexString
  return SignedTransfer(id:id,payload:["encoded":"0x" + output.encoded.hexString])
 }
}
