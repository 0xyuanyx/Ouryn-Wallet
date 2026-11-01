import Foundation

// 금액 요청 QR · 네트워크별 받는 주소
// QR 내용은 Solana Pay 전송 요청 형식을 따름 → 다른 솔라나 지갑도 읽을 수 있음
// solana:<받는 주소>?amount=<달러>&spl-token=<토큰 주소>&label=Ouryn
// https://docs.solanapay.com/spec

/// 솔라나 위 달러 토큰 주소 (메인넷 · 테스트 통장이면 devnet: Circle USDC 만)
var MINTS: [String: String] { mintTable(test: Testnet.on) }
func mintTable(test: Bool) -> [String: String] {
    test ? ["usdc": "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"]
         : ["usdc": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "usdt": "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"]
}

/// 자산마다 받는 네트워크
let ASSET_NET: [String: String] = [
    "usdc": DOLLAR_NET, "usdt": DOLLAR_NET, "sol": DOLLAR_NET, "eth": "이더리움", "btc": "비트코인",
    "ada": "카르다노", "night": "카르다노", "trx": "트론", "mnt": "맨틀", "avax": "Avalanche C-Chain", "usdt0":"맨틀",
]

struct PayRequest: Equatable, Hashable {
    var to: String
    var network: String? = nil
    var usd: Double? = nil
    var asset: String? = nil
    var test = false      // 테스트넷 주소 (테스트 통장에서만 보냄)
    var mainnet = false   // 실제 네트워크라고 밝힌 주소 (테스트 통장에서는 못 보냄)
    var qty: String? = nil // 정확한 코인 수량 (ERC-681 처럼 최소 단위로 받은 요청). 있으면 usd 대신 이 값을 그대로 씀
}

/// 소수점 둘째 자리까지, 과학 표기 없이 (예: 12, 0.5, 30.25)
private func plainAmount(_ v: Double) -> String {
    var s = String(format: "%.2f", (v * 100).rounded() / 100)
    while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
    return s
}

/// 공유용 표준 링크 (Solana Pay) — 다른 솔라나 지갑도 금액까지 읽음. 길어서 QR 에는 안 씀
func payURI(to: String, usd: Double?, asset: String? = "usdc") -> String {
    guard let u = usd, u > 0 else { return "solana:\(to)" }
    var q = ["amount=\(plainAmount(u))"]
    if let a = asset, let m = MINTS[a] { q.append("spl-token=\(m)") }
    q.append("label=Ouryn")
    return "solana:\(to)?" + q.joined(separator: "&")
}

/// 원형 QR 에 넣는 짧은 내용 — 짧을수록 점이 크고 적어짐
/// - 금액 없음: "solana:<주소>" (표준 → 어느 솔라나 지갑이든 읽음, 37칸)
/// - 금액 있음: "ouryn:<주소>?a=12.5&t=c" (Ouryn 전용 짧은 형식, 41칸)
///   표준 형식은 토큰 주소(44자) 때문에 53칸까지 커져서 점이 자글자글해짐
func qrPayload(to: String, usd: Double?, asset: String = "usdc") -> String {
    guard let u = usd, u > 0 else { return "solana:\(to)" }
    return "ouryn:\(to)?a=\(plainAmount(u))&t=\(asset == "usdt" ? "t" : "c")"
}

/// QR·붙여넣기에서 읽은 글자 → 요청. 그냥 주소만 있어도 됨
func parsePay(_ raw: String) -> PayRequest? {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // 주소 모양으로 네트워크가 갈리는 것: 비트코인 tb1/bc1 · 카르다노 addr_test1/addr1
    if Testnet.looksTest(s) || Testnet.looksMain(s) {
        let test = Testnet.looksTest(s)
        guard let n = WalletNetwork.allCases.first(where: { WalletKeys.valid(s, network: $0, test: test) }) else { return nil }
        return PayRequest(to: s, network: n.rawValue, test: test, mainnet: !test)
    }
    if s.lowercased().hasPrefix("ethereum:") { return parseEIP681(String(s.dropFirst("ethereum:".count))) }
    if isAddr(s) {
        let net: String? = s.hasPrefix("0x") ? nil : WalletNetwork.allCases.first(where:{ WalletKeys.valid(s,network:$0) })?.rawValue
        return PayRequest(to:s,network:net)
    }
    if s.lowercased().hasPrefix("ouryn:") { return parseOuryn(String(s.dropFirst("ouryn:".count))) }
    guard s.lowercased().hasPrefix("solana:") else { return nil }
    let body = String(s.dropFirst("solana:".count))
    let parts = body.split(separator: "?", maxSplits: 1).map(String.init)
    guard let to = parts.first, WalletKeys.valid(to, network: .solana) else { return nil }
    var req = PayRequest(to: to, network: DOLLAR_NET)
    let query = parts.count > 1 ? parts[1] : ""
    // cluster=devnet → 테스트넷 요청
    req.test = query.split(separator: "&").contains { $0 == "cluster=devnet" }
    if !query.isEmpty {
        for kv in query.split(separator: "&") {
            let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
            guard p.count == 2 else { continue }
            let v = p[1].removingPercentEncoding ?? p[1]
            if p[0] == "amount", let d = Double(v), d > 0, d.isFinite { req.usd = d }
            if p[0] == "spl-token" {
                guard let a = mintTable(test: req.test).first(where: { $0.value == v })?.key else { return nil } // 모르는 토큰은 받지 않음
                req.asset = a
            }
        }
    }
    if req.usd != nil && req.asset == nil { return nil } // SOL 자체 요청은 아직 지원 안 함
    return req
}

/// "ethereum:[pay-]<주소>[@<체인 번호>][/<함수>][?<값들>]" (ERC-681 · https://eips.ethereum.org/EIPS/eip-681)
/// - 주소만: 그 주소로 보내기. value=<wei> 가 있으면 그 체인 기본 코인 수량
/// - /transfer: <주소> 는 토큰 컨트랙트, address= 가 받는 사람, uint256= 가 최소 단위 수량
///   → 앱이 아는 토큰(USDC·USDT·USDT0)일 때만. 받는 사람을 컨트랙트 주소로 바꿔 읽지 않음
/// - 그 밖의 함수(approve 등), 모르는 값·같은 값 두 번·잘못된 체인 번호는 뜻을 버리고 받지 않고 거부
/// - 수량이나 함수가 있으면 체인 번호가 꼭 있어야 함 (어느 네트워크 수량인지 모르면 거부)
private func parseEIP681(_ body: String) -> PayRequest? {
    var b = body
    if b.hasPrefix("pay-") { b = String(b.dropFirst(4)) }
    let split = b.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    let head = split[0]
    let query = split.count > 1 ? split[1] : nil
    let path = head.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    let function = path.count > 1 ? path[1] : nil
    let at = path[0].split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    let target = at[0]
    guard !target.isEmpty else { return nil }
    // 체인 번호를 적었으면 숫자이면서 앱이 아는 체인이어야 함 (@invalid 를 '체인 없음'으로 넘기지 않음)
    var chain: Int? = nil
    if at.count > 1 {
        guard !at[1].isEmpty, at[1].allSatisfy({ $0 >= "0" && $0 <= "9" }), let c = Int(at[1]), Testnet.evm(chain: c) != nil else { return nil }
        chain = c
    }
    // 값들: key=value, 같은 key 두 번은 거부
    var params: [String: String] = [:]
    if let query {
        guard !query.isEmpty else { return nil }
        for kv in query.split(separator: "&", omittingEmptySubsequences: false) {
            let p = kv.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 2, !p[0].isEmpty, params[p[0]] == nil, let v = p[1].removingPercentEncoding, !v.isEmpty else { return nil }
            params[p[0]] = v
        }
    }
    // 수수료 힌트는 앱이 직접 계산하므로 읽지 않아도 보낼 대상·수량이 바뀌지 않음
    let feeHints: Set<String> = ["gas", "gasLimit", "gasPrice"]

    switch function {
    case nil:
        guard Set(params.keys).subtracting(feeHints).isSubset(of: ["value"]) else { return nil }
        guard let value = params["value"] else {
            // 주소만 (+ 수수료 힌트): 체인이 없으면 0x 네트워크 셋 중에서 직접 고름
            guard let pick = Testnet.evm(chain: chain ?? 1), WalletKeys.valid(target, network: pick.0, test: pick.1) else { return nil }
            return PayRequest(to: target, network: chain == nil ? nil : pick.0.rawValue, test: pick.1, mainnet: chain != nil && !pick.1)
        }
        guard let c = chain, let pick = Testnet.evm(chain: c), WalletKeys.valid(target, network: pick.0, test: pick.1),
              let raw = ExactAmount.erc681(value), raw != "0",
              let qty = ExactAmount.text(raw: raw, decimals: pick.0.decimals(pick.0.native)) else { return nil }
        return PayRequest(to: target, network: pick.0.rawValue, asset: pick.0.native, test: pick.1, mainnet: !pick.1, qty: qty)
    case "transfer"?:
        guard Set(params.keys).subtracting(feeHints).isSubset(of: ["address", "uint256"]),
              let c = chain, let pick = Testnet.evm(chain: c),
              let recipient = params["address"], WalletKeys.valid(recipient, network: pick.0, test: pick.1),
              recipient.lowercased() != target.lowercased(),
              let asset = pick.0.assets.first(where: { pick.0.contract($0, test: pick.1)?.lowercased() == target.lowercased() })
        else { return nil }
        var req = PayRequest(to: recipient, network: pick.0.rawValue, asset: asset, test: pick.1, mainnet: !pick.1)
        if let amount = params["uint256"] {
            guard let raw = ExactAmount.erc681(amount), raw != "0",
                  let qty = ExactAmount.text(raw: raw, decimals: pick.0.decimals(asset)) else { return nil }
            req.qty = qty
        }
        return req
    default:
        return nil   // approve 등 송금이 아닌 함수는 지원하지 않음
    }
}

/// "ouryn:<주소>?a=12.5&t=c" 읽기 (c = 서클 달러, t = 테더 달러)
/// 테스트 통장 QR: "ouryn:<주소>?n=eth&x=t" (n = 네트워크, x=t = 테스트넷)
private func parseOuryn(_ body: String) -> PayRequest? {
    let parts = body.split(separator: "?", maxSplits: 1).map(String.init)
    let pairs = (parts.count > 1 ? parts[1] : "").split(separator: "&").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
    let test = pairs.contains { $0 == ["x", "t"] }
    let net = pairs.first { $0.count == 2 && $0[0] == "n" }.flatMap { Testnet.network(code: $0[1]) } ?? .solana
    guard let to = parts.first, WalletKeys.valid(to, network: net, test: test) else { return nil }
    var req = PayRequest(to: to, network: net.rawValue, test: test)
    if parts.count > 1 && net == .solana {
        for kv in parts[1].split(separator: "&") {
            let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
            guard p.count == 2 else { continue }
            if p[0] == "a", let d = Double(p[1]), d > 0, d.isFinite { req.usd = d }
            if p[0] == "t" {
                switch p[1] {
                case "c": req.asset = "usdc"
                case "t": req.asset = "usdt"
                default: return nil // 모르는 돈은 받지 않음
                }
            }
        }
    }
    if req.usd != nil && req.asset == nil { req.asset = "usdc" }
    return req
}

// MARK: - 자산 이름·수량 표시

/// 서클 달러 / 테더 달러 / 이더리움 …
func assetFullName(_ id: String) -> String {
    let m = assetMeta(id)
    return (id == "usdc" || id == "usdt") ? (m.sub ?? m.name) : m.name
}

/// 달러는 "30.00달러", 코인은 "0.01개"
func assetAmount(_ id: String, _ qty: Double) -> String {
    (id == "usdc" || id == "usdt") ? dollar(qty) : qtyText(qty)
}
