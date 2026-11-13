import Foundation
import CryptoKit
import WalletCore

enum SolanaTransferEngine {
 static var rpcURL: String { ChainAPI.solanaRPC.absoluteString }
 static func rpc(_ method:String,_ params:[Any]) async throws -> Any {
  let json = try await MultiChainAPI.request(rpcURL,body:["jsonrpc":"2.0","id":1,"method":method,"params":params])
  guard json["error"] == nil, let result = json["result"] else { throw TransferError.invalid("솔라나 서버 요청에 실패했어요") }; return result
 }
 static func quote(owner:String,to:String,asset:String,amount:String) async throws -> TransferQuote {
  guard WalletNetwork.solana.assets.contains(asset), WalletKeys.valid(to,network:.solana), owner != to else { throw TransferError.invalid("받는 솔라나 주소를 확인해주세요") }
  let raw = try ExactAmount.parse(amount,decimals:WalletNetwork.solana.decimals(asset))
  guard let quantity = UInt64(raw), quantity > 0 else { throw TransferError.invalid("수량을 확인해주세요") }
  let genesis = try await rpc("getGenesisHash",[]) as? String
  guard genesis == (Testnet.on ? Testnet.solanaGenesis : "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d") else { throw TransferError.invalid(Testnet.on ? "솔라나 devnet 연결을 확인해주세요" : "솔라나 메인넷 연결을 확인해주세요") }
  guard let latest = try await rpc("getLatestBlockhash",[["commitment":"confirmed"]]) as? [String:Any], let blockhash = (latest["value"] as? [String:Any])?["blockhash"] as? String, let validHeight = (latest["value"] as? [String:Any])?["lastValidBlockHeight"] as? NSNumber,
    let balance = try await rpc("getBalance",[owner,["commitment":"confirmed"]]) as? [String:Any], let lamports = balance["value"] as? NSNumber else { throw TransferError.invalid("잔액과 최신 블록을 확인하지 못했어요") }
  var draft: [String:Any] = ["blockhash":blockhash,"validHeight":validHeight.uint64Value]
  var cap: UInt64 = 10000
  if asset != "sol" {
   guard let mint = MINTS[asset], let from = SolanaAddress(string:owner)?.defaultTokenAddress(tokenMintAddress:mint), let destination = SolanaAddress(string:to)?.defaultTokenAddress(tokenMintAddress:mint) else { throw TransferError.invalid("토큰 계정을 계산하지 못했어요") }
   guard let token = try await rpc("getTokenAccountBalance",[from]) as? [String:Any], let value = token["value"] as? [String:Any], let count = value["amount"] as? String,
         UInt64(count) ?? 0 >= quantity, (value["decimals"] as? Int) == 6 else { throw TransferError.invalid("토큰 잔액이 부족하거나 소수점 정보가 달라요") }
   let info = try await rpc("getAccountInfo",[destination,["encoding":"jsonParsed"]]) as? [String:Any]
   let create = info?["value"] is NSNull
   if create {
    guard let rent = try await rpc("getMinimumBalanceForRentExemption",[165]) as? NSNumber else { throw TransferError.invalid("토큰 계정 생성 비용을 확인하지 못했어요") }; cap += rent.uint64Value
   } else {
    guard let account = info?["value"] as? [String:Any], account["owner"] as? String == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", let data = account["data"] as? [String:Any], let parsed = data["parsed"] as? [String:Any], let details = parsed["info"] as? [String:Any], details["mint"] as? String == mint, details["owner"] as? String == to else { throw TransferError.invalid("받는 토큰 계정이 올바르지 않아요") }
   }
   draft["senderToken"] = from; draft["recipientToken"] = destination; draft["create"] = create
  }
  guard lamports.uint64Value >= cap, lamports.uint64Value - cap >= (asset == "sol" ? quantity : 0) else { throw TransferError.invalid("수수료와 계정 생성 비용을 충당할 SOL이 부족해요") }
  return TransferQuote(network:.solana,asset:asset,owner:owner,recipient:to,raw:raw,fee:Decimal(cap)/1000000000,expires:Date().addingTimeInterval(45),draft:draft,parameter:nil,maxFee:Int64(cap))
 }
 static func preflight(_ signed:SignedTransfer) async throws {
  guard let encoded = signed.payload["encoded"] as? String, let bytes = Base58.decodeNoCheck(string:encoded), bytes.count > 65 else { throw TransferError.invalid("전송 데이터가 올바르지 않아요") }
  let message = bytes.dropFirst(65).base64EncodedString()
  let fee = try await rpc("getFeeForMessage",[message,["commitment":"confirmed"]]) as? [String:Any]
  guard let lamports = fee?["value"] as? NSNumber, lamports.int64Value <= 10000 else { throw TransferError.invalid("수수료가 확인한 상한을 넘거나 요청이 만료됐어요") }
  let data = bytes.base64EncodedString()
  let sim = try await rpc("simulateTransaction",[data,["encoding":"base64","sigVerify":true]]) as? [String:Any]
  guard let value = sim?["value"] as? [String:Any], value["err"] is NSNull else { throw TransferError.invalid("네트워크 전송 사전 검사에 실패했어요") }
 }
 static func broadcast(_ signed:SignedTransfer) async throws {
  guard let encoded = signed.payload["encoded"] as? String, let bytes = Base58.decodeNoCheck(string:encoded) else { throw TransferError.invalid("전송 데이터가 올바르지 않아요") }
  let data = bytes.base64EncodedString()
  let id = try await rpc("sendTransaction",[data,["encoding":"base64","skipPreflight":false]]) as? String
  guard id == signed.id else { throw TransferError.invalid("전송 응답을 확인하지 못했어요") }
 }
 static func status(_ hash:String) async throws -> TxStatus {
  let result = try await rpc("getSignatureStatuses",[[hash],["searchTransactionHistory":true]]) as? [String:Any]
  guard let values = result?["value"] as? [Any], let value = values.first as? [String:Any] else { return .pending }
  if !(value["err"] is NSNull) { return .failed }
  return value["confirmationStatus"] as? String == "finalized" ? .done : .pending
 }
}
extension WalletKeys {
 static func signSolana(_ quote:TransferQuote) throws -> SignedTransfer {
  guard quote.network == .solana, quote.expires > Date(), let wallet = signingWallet(), WalletKeys.signingAddress(wallet,.solana) == quote.owner,
   let amount = UInt64(quote.raw), let blockhash = quote.draft["blockhash"] as? String,
   let ownerKey = Base58.decodeNoCheck(string:quote.owner), let blockKey = Base58.decodeNoCheck(string:blockhash) else { throw TransferError.invalid("확인이 만료됐거나 지갑을 열 수 없어요") }
  let create = quote.draft["create"] as? Bool == true
  let expected: SolanaEvidence.Transfer
  let token: (mint:String, from:String, to:String)?
  if quote.asset == "sol" {
   guard let to = Base58.decodeNoCheck(string:quote.recipient) else { throw TransferError.invalid("받는 솔라나 주소를 확인해주세요") }
   expected = .sol(to:to,lamports:amount); token = nil
  } else {
   // 토큰 계정은 견적에 적힌 값을 그대로 쓰지 않고 여기서 다시 계산해 같은지 확인
   guard let mint = MINTS[quote.asset], let from = quote.draft["senderToken"] as? String, let to = quote.draft["recipientToken"] as? String,
         from == SolanaAddress(string:quote.owner)?.defaultTokenAddress(tokenMintAddress:mint),
         to == SolanaAddress(string:quote.recipient)?.defaultTokenAddress(tokenMintAddress:mint),
         let mintKey = Base58.decodeNoCheck(string:mint), let fromKey = Base58.decodeNoCheck(string:from),
         let toKey = Base58.decodeNoCheck(string:to), let walletKey = Base58.decodeNoCheck(string:quote.recipient)
   else { throw TransferError.invalid("토큰 계정을 확인하지 못했어요") }
   expected = .token(mint:mintKey,from:fromKey,to:toKey,wallet:walletKey,amount:amount,decimals:6,create:create); token = (mint,from,to)
  }
  let input = SolanaSigningInput.with {
   $0.privateKey = WalletKeys.signingKey(wallet,.solana).data; $0.recentBlockhash = blockhash
   if let token, create {
    $0.createAndTransferTokenTransaction = SolanaCreateAndTransferToken.with {
     $0.recipientMainAddress = quote.recipient; $0.tokenMintAddress = token.mint
     $0.senderTokenAddress = token.from; $0.recipientTokenAddress = token.to; $0.amount = amount; $0.decimals = 6
    }
   } else if let token {
    $0.tokenTransferTransaction = SolanaTokenTransfer.with {
     $0.tokenMintAddress = token.mint; $0.senderTokenAddress = token.from; $0.recipientTokenAddress = token.to; $0.amount = amount; $0.decimals = 6
    }
   } else { $0.transferTransaction = SolanaTransfer.with { $0.recipient = quote.recipient; $0.value = amount } }
  }
  let output:SolanaSigningOutput = AnySigner.sign(input:input,coin:.solana)
  // 서명된 바이트를 다시 읽어서 보내는 사람·블록·지시(받는 곳, 토큰, 수량)가 견적과 정확히 같은지, 서명이 맞는지 확인
  guard output.error == .ok, let bytes = Base58.decodeNoCheck(string:output.encoded), let evidence = try? SolanaEvidence.parse(bytes),
        evidence.matches(owner:ownerKey,blockhash:blockKey,transfer:expected),
        let signer = try? CryptoKit.Curve25519.Signing.PublicKey(rawRepresentation:ownerKey),
        signer.isValidSignature(evidence.signatures[0],for:evidence.message)
  else { throw TransferError.invalid("서명 검증에 실패했어요") }
  let id = Base58.encodeNoCheck(data:evidence.signatures[0])
  return SignedTransfer(id:id,payload:["encoded":output.encoded])
 }
}
