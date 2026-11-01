import Foundation

struct ChainReceipt {
 let hash:String
 let network:WalletNetwork
 let asset:String
 let raw:String
 let sender:String
 let date:Date
}
enum ReceiveHistory {
 /// Confirmed issuer-contract transfers only. These rows do not manufacture a deposit from aggregate balance changes.
 static func tron(_ address:String) async throws -> [ChainReceipt] {
  var components = URLComponents(string:TronTransfer.base + "/v1/accounts/" + address + "/transactions/trc20")!
  components.queryItems = [URLQueryItem(name:"only_confirmed",value:"true"),URLQueryItem(name:"only_to",value:"true"),URLQueryItem(name:"limit",value:"50"),URLQueryItem(name:"contract_address",value:WalletNetwork.tron.contract("usdt"))]
  var request = URLRequest(url:components.url!); request.timeoutInterval = 20
  let (data,response) = try await URLSession.shared.data(for:request)
  guard let http = response as? HTTPURLResponse, http.statusCode == 200, let json = try JSONSerialization.jsonObject(with:data) as? [String:Any], json["success"] as? Bool == true, let rows = json["data"] as? [[String:Any]] else { throw MultiChainAPI.APIError.invalid }
  let events:[ChainReceipt] = rows.compactMap { row in
   guard row["to"] as? String == address, row["type"] as? String == "Transfer", let token = row["token_info"] as? [String:Any], token["address"] as? String == WalletNetwork.tron.contract("usdt"), token["decimals"] as? Int == 6,
      let hash = row["transaction_id"] as? String, let raw = row["value"] as? String, let count = Decimal(string:raw), count > 0, ExactAmount.bytes(raw) != nil,
      let sender = row["from"] as? String, let millis = row["block_timestamp"] as? NSNumber else { return nil }
   return ChainReceipt(hash:hash,network:.tron,asset:"usdt",raw:raw,sender:sender,date:Date(timeIntervalSince1970:millis.doubleValue/1000))
  }
  return Dictionary(grouping:events,by:{ $0.hash }).values.compactMap { receipts in
   guard let first = receipts.first else { return nil }
   let total = receipts.reduce(Decimal(0)) { $0 + (Decimal(string:$1.raw) ?? 0) }
   let raw = NSDecimalNumber(decimal:total).stringValue
   guard ExactAmount.bytes(raw) != nil else { return nil }
   return ChainReceipt(hash:first.hash,network:first.network,asset:first.asset,raw:raw,sender:first.sender,date:first.date)
  }
 }

 /// 이더리움 입금(ETH · USDC): 탐색기(Blockscout)에서 내 주소로 들어온 확정 거래만 읽음. 최근 30일치.
 static func ethereum(_ address:String) async throws -> [ChainReceipt] {
  let base = Testnet.on ? "https://eth-sepolia.blockscout.com/api/v2" : "https://eth.blockscout.com/api/v2"
  let since = Date().addingTimeInterval(-30 * 86400)
  let mine = address.lowercased()
  func fetch(_ path:String) async throws -> [[String:Any]] {
   guard let url = URL(string:base + "/addresses/" + address + path) else { throw MultiChainAPI.APIError.invalid }
   var request = URLRequest(url:url); request.timeoutInterval = 20
   request.setValue("application/json", forHTTPHeaderField:"Accept")
   let (data,response) = try await URLSession.shared.data(for:request)
   guard let http = response as? HTTPURLResponse, http.statusCode == 200, let json = try JSONSerialization.jsonObject(with:data) as? [String:Any], let rows = json["items"] as? [[String:Any]] else { throw MultiChainAPI.APIError.invalid }
   return rows
  }
  func when(_ row:[String:Any]) -> Date? {
   guard let text = row["timestamp"] as? String else { return nil }
   let precise = ISO8601DateFormatter(); precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
   return precise.date(from:text) ?? ISO8601DateFormatter().date(from:text)
  }
  func hash(_ o:Any?) -> String? { (o as? [String:Any])?["hash"] as? String }
  var out:[ChainReceipt] = []
  for row in try await fetch("/transactions?filter=to") {
   guard row["status"] as? String == "ok", hash(row["to"])?.lowercased() == mine,
      let id = row["hash"] as? String, let from = hash(row["from"]), let raw = row["value"] as? String,
      let count = Decimal(string:raw), count > 0, ExactAmount.bytes(raw) != nil,
      let date = when(row), date > since else { continue }
   out.append(ChainReceipt(hash:id,network:.ethereum,asset:"eth",raw:raw,sender:from,date:date))
  }
  // 토큰은 따로 읽고, 실패해도 ETH 는 그대로 돌려줌
  if let usdc = WalletNetwork.ethereum.contract("usdc")?.lowercased(), let rows = try? await fetch("/token-transfers?type=ERC-20&filter=to") {
   for row in rows {
    let token = row["token"] as? [String:Any]
    let tokenAddress = (token?["address_hash"] as? String ?? token?["address"] as? String)?.lowercased()
    let total = row["total"] as? [String:Any]
    guard tokenAddress == usdc, hash(row["to"])?.lowercased() == mine,
       let id = (row["transaction_hash"] as? String) ?? (row["tx_hash"] as? String), let from = hash(row["from"]),
       let raw = total?["value"] as? String, let count = Decimal(string:raw), count > 0, ExactAmount.bytes(raw) != nil,
       let date = when(row), date > since else { continue }
    out.append(ChainReceipt(hash:id,network:.ethereum,asset:"usdc",raw:raw,sender:from,date:date))
   }
  }
  return out
 }

 /// 동기화 때 한 번에 읽는 입금 내역 (둘 다 못 읽으면 nil)
 static func all(_ a:ChainAddrs, ethereum useEthereum:Bool) async -> [ChainReceipt]? {
  var out:[ChainReceipt] = []
  var ok = false
  if let tron = a.tron, let r = try? await ReceiveHistory.tron(tron) { out += r; ok = true }
  if useEthereum, let r = try? await ReceiveHistory.ethereum(a.ethereum) { out += r; ok = true }
  return ok ? out : nil
 }
}
