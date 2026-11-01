import Foundation

struct NetworkSnapshot {
 let network: WalletNetwork
 var balances: [String: String]?
 var error: String?
}
enum MultiChainAPI {
 static func request(_ url: String, body: [String: Any]) async throws -> [String: Any] {
  var r = URLRequest(url: URL(string:url)!); r.httpMethod = "POST"; r.timeoutInterval = 20
  r.setValue("application/json", forHTTPHeaderField:"Content-Type")
  r.httpBody = try JSONSerialization.data(withJSONObject:body)
  let (data,response) = try await URLSession.shared.data(for:r)
  guard let http = response as? HTTPURLResponse else { throw APIError.invalid }
  guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
  guard let json = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw APIError.invalid }
  return json
 }
 enum APIError: LocalizedError {
  case invalid, mismatch, http(Int)
  var errorDescription: String? {
   let server = Testnet.on ? "테스트넷 서버" : "잔액 서버"
   switch self {
   case .mismatch: return "연결된 네트워크가 달라요"
   case .http(429): return server + "가 요청이 많다고 잠시 막았어요 (429)"
   case .http(let code): return server + " 응답 오류 (\(code))"
   case .invalid: return server + "에 연결하지 못했어요"
   }
  }
 }
 static func rpc(_ net: WalletNetwork, _ method: String, _ params: [Any]) async throws -> String {
  guard let url = net.rpc else { throw APIError.invalid }
  let json = try await request(url,body:["jsonrpc":"2.0","id":1,"method":method,"params":params])
  guard json["error"] == nil, let value = json["result"] as? String else { throw APIError.invalid }
  return value
 }
 static func fetch(_ addresses: ChainAddrs) async -> [NetworkSnapshot] {
  await withTaskGroup(of:NetworkSnapshot.self) { group in
   for net in [WalletNetwork.tron, .ethereum, .mantle, .avalanche] {
    group.addTask {
     do {
      guard WalletKeys.passed(net.rawValue) else { throw APIError.invalid }
      let balances: [String:String]
      if net == .tron { guard let address = addresses.tron else { throw APIError.invalid }; balances = try await tron(address) }
      else { balances = try await evm(addresses.ethereum, net:net) }
      return NetworkSnapshot(network:net,balances:balances)
     } catch { return NetworkSnapshot(network:net,error:error.localizedDescription) }
    }
   }
   var all = [NetworkSnapshot](); for await item in group { all.append(item) }; return all
  }
 }
 static func evm(_ address: String, net: WalletNetwork) async throws -> [String:String] {
  let id = try await rpc(net,"eth_chainId",[])
  guard ExactAmount.hexDecimal(id) == Decimal(net.chainID ?? -1) else { throw APIError.mismatch }
  var balances = [String:String]()
  let native = try await rpc(net,"eth_getBalance",[address,"latest"])
  guard let n = ExactAmount.hexDecimal(native) else { throw APIError.invalid }
  balances[net.native] = NSDecimalNumber(decimal:n).stringValue
  for asset in net.assets where net.contract(asset) != nil {
   let call = "0x70a08231" + String(repeating:"0",count:24) + address.dropFirst(2).lowercased()
   let hex = try await rpc(net,"eth_call",[["to":net.contract(asset)!,"data":call],"latest"])
   guard let amount = ExactAmount.hexDecimal(hex) else { throw APIError.invalid }
   balances[asset] = NSDecimalNumber(decimal:amount).stringValue
  }
  return balances
 }
 static func tron(_ address: String) async throws -> [String:String] {
  let base = TronTransfer.base
  let account = try await request(base + "/wallet/getaccount",body:["address":address,"visible":true])
  guard account["Error"] == nil else { throw APIError.invalid }
  let trx = (account["balance"] as? NSNumber)?.stringValue ?? "0"
  guard let hex = WalletKeys.tronHex(address) else { throw APIError.invalid }
  let parameter = String(repeating:"0",count:24) + hex.suffix(40)
  let json = try await request(base + "/wallet/triggerconstantcontract",body:["owner_address":address,"contract_address":WalletNetwork.tron.contract("usdt")!,"function_selector":"balanceOf(address)","parameter":parameter,"visible":true])
  guard (json["result"] as? [String:Any])?["result"] as? Bool == true,
   let value = (json["constant_result"] as? [String])?.first, let quantity = ExactAmount.hexDecimal(value) else { throw APIError.invalid }
  return ["trx":trx,"usdt":NSDecimalNumber(decimal:quantity).stringValue]
 }
}
