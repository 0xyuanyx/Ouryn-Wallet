import Foundation

// 메인넷 잔액·시세 읽기 (키 없이 주소만 사용 — 읽기 전용)
//   솔라나   api.mainnet-beta.solana.com  getBalance · getTokenAccountsByOwner(USDC/USDT)
//   이더리움 ethereum-rpc.publicnode.com   eth_getBalance
//   비트코인 mempool.space                 /api/address/{주소}
//   카르다노 api.koios.rest (v1)           address_info · address_assets (NIGHT)
//   시세     api.coingecko.com             simple/price · market_chart (원화)
// 공개 무료 서버라 느리거나 가끔 막힐 수 있음 → 실패한 체인은 이전 값을 유지하고 표시만 함

enum ChainAPI {
    // 테스트 통장이면 테스트넷 서버 (Testnet.swift)
    static var solanaRPC: URL { URL(string: Testnet.on ? "https://api.devnet.solana.com" : "https://api.mainnet-beta.solana.com")! }
    static var ethRPC: URL { URL(string: Testnet.on ? "https://ethereum-sepolia-rpc.publicnode.com" : "https://ethereum-rpc.publicnode.com")! }
    static var mempool: String { Testnet.on ? "https://mempool.space/testnet4/api/address/" : "https://mempool.space/api/address/" }
    static var koios: String { Testnet.on ? "https://preprod.koios.rest/api/v1/" : "https://api.koios.rest/api/v1/" }
    static let gecko = "https://api.coingecko.com/api/v3/"

    /// NIGHT (Midnight) — 카르다노 네이티브 토큰, 소수점 6자리 (cardano-token-registry)
    static let nightPolicy = "0691b2fecca1ac4f53cb6dfb00b7013e561d1f34403b957cbb5af1fa"
    static let nightName = "4e49474854" // "NIGHT"

    /// 앱 자산 id → CoinGecko id
    static let geckoIds: [String: String] = [
        "usdc": "usd-coin", "usdt": "tether", "sol": "solana", "eth": "ethereum",
        "btc": "bitcoin", "ada": "cardano", "night": "midnight-3", "trx": "tron", "mnt": "mantle", "avax": "avalanche-2",
    ]

    struct SolanaBal { var sol: Double; var usdc: Double; var usdt: Double }
    struct CardanoBal { var ada: Double; var night: Double }

    /// nil = 그 체인은 이번에 못 읽음
    struct Balances {
        var solana: SolanaBal?
        var eth: Double?
        var btc: Double?
        var cardano: CardanoBal?
        /// 못 읽은 이유 (네트워크 이름 → 한 줄)
        var reasons: [String: String] = [:]
        var failed: [String] {
            var f: [String] = []
            if solana == nil { f.append("솔라나") }
            if eth == nil { f.append("이더리움") }
            if btc == nil { f.append("비트코인") }
            if cardano == nil { f.append("카르다노") }
            return f
        }
    }

    struct Quote { var krw: Double; var change: Double }

    // MARK: 잔액

    static func balances(_ a: ChainAddrs, only nets: Set<String>) async -> Balances {
        async let s = attempt(nets.contains("솔라나")) { try await readSolana(a.solana) }
        async let e = attempt(nets.contains("이더리움")) { try await readEthereum(a.ethereum) }
        async let b = attempt(nets.contains("비트코인")) { try await readBitcoin(a.bitcoin) }
        async let c = attempt(nets.contains("카르다노")) { try await readCardano(a.cardano) }
        let (sv, ev, bv, cv) = await (s, e, b, c)
        var out = Balances(solana: sv.0, eth: ev.0, btc: bv.0, cardano: cv.0)
        for (net, why) in [("솔라나", sv.1), ("이더리움", ev.1), ("비트코인", bv.1), ("카르다노", cv.1)] {
            if let why { out.reasons[net] = why }
        }
        return out
    }

    /// 꺼진 체인은 (nil, nil), 실패하면 (nil, 이유)
    private static func attempt<T>(_ on: Bool, _ job: () async throws -> T) async -> (T?, String?) {
        guard on else { return (nil, nil) }
        do { return (try await job(), nil) } catch { return (nil, reason(error)) }
    }

    /// 화면에 보여줄 실패 이유 한 줄
    static func reason(_ error: Error) -> String {
        if let h = error as? HTTPError {
            switch h.code {
            case 429: return "서버가 요청이 많다고 잠시 막았어요 (429)"
            case -2: return "서버가 요청을 거절했어요"
            case -3: return "서버 응답을 읽지 못했어요"
            case 500...: return "서버 오류 (\(h.code))"
            case 1..<500: return "서버가 요청을 받지 않았어요 (\(h.code))"
            default: return "서버에 연결하지 못했어요"
            }
        }
        if let u = error as? URLError {
            switch u.code {
            case .timedOut: return "서버 응답이 너무 늦어요"
            case .notConnectedToInternet, .networkConnectionLost: return "인터넷 연결을 확인해주세요"
            case .cancelled: return "확인이 중간에 멈췄어요"
            default: return "서버에 연결하지 못했어요"
            }
        }
        if let t = error as? TransferError, case .invalid(let m) = t { return m }
        if error is DecodingError || (error as NSError).domain == NSCocoaErrorDomain { return "서버 응답을 읽지 못했어요" }
        return "서버에 연결하지 못했어요"
    }

    static func solana(_ addr: String, on: Bool = true) async -> SolanaBal? {
        guard on else { return nil }
        return try? await readSolana(addr)
    }

    private static func readSolana(_ addr: String) async throws -> SolanaBal {
        let r = try await rpc(solanaRPC, "getBalance", [addr])
        let lamports = num(dig(r, "value")) ?? 0
        async let usdc = splToken(addr, MINTS["usdc"] ?? "")
        async let usdt = splToken(addr, MINTS["usdt"] ?? "")
        return try await SolanaBal(sol: lamports / 1e9, usdc: usdc, usdt: usdt)
    }

    private static func splToken(_ owner: String, _ mint: String) async throws -> Double {
        guard !mint.isEmpty else { return 0 } // 테스트넷엔 USDT 가 없음
        let r = try await rpc(solanaRPC, "getTokenAccountsByOwner", [owner, ["mint": mint], ["encoding": "jsonParsed"]])
        let list = dig(r, "value") as? [Any] ?? []
        return list.reduce(0.0) { sum, acc in
            let s = dig(acc, "account", "data", "parsed", "info", "tokenAmount", "uiAmountString") as? String
            return sum + (Double(s ?? "") ?? 0)
        }
    }

    static func ethereum(_ addr: String, on: Bool = true) async -> Double? {
        guard on else { return nil }
        return try? await readEthereum(addr)
    }

    private static func readEthereum(_ addr: String) async throws -> Double {
        let r = try await rpc(ethRPC, "eth_getBalance", [addr, "latest"])
        guard let hex = r as? String, let v = hexToDouble(hex) else { throw HTTPError(code: -3) }
        return v / 1e18
    }

    static func bitcoin(_ addr: String, on: Bool = true) async -> Double? {
        guard on else { return nil }
        return try? await readBitcoin(addr)
    }

    private static func readBitcoin(_ addr: String) async throws -> Double {
        let data = try await BitcoinTransfer.get("/address/" + addr)
        guard let j = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw HTTPError(code: -3) }
        func part(_ k: String) -> Double {
            (num(dig(j, k, "funded_txo_sum")) ?? 0) - (num(dig(j, k, "spent_txo_sum")) ?? 0)
        }
        // 확인된 것 + 아직 블록에 안 들어간 것(메모리풀)
        return (part("chain_stats") + part("mempool_stats")) / 1e8
    }

    static func cardano(_ addr: String, on: Bool = true) async -> CardanoBal? {
        guard on else { return nil }
        return try? await readCardano(addr)
    }

    private static func readCardano(_ addr: String) async throws -> CardanoBal {
        let body = ["_addresses": [addr]]
        async let infoJ = post(URL(string: koios + "address_info")!, body)
        async let assetsJ = post(URL(string: koios + "address_assets")!, body)
        let info = try await infoJ as? [Any] ?? []
        let lovelace = info.first.flatMap { Double(dig($0, "balance") as? String ?? "") } ?? 0 // 한 번도 안 쓴 주소는 빈 배열
        let assets = try await assetsJ as? [Any] ?? []
        var night = 0.0
        for row in assets {
            guard dig(row, "policy_id") as? String == nightPolicy,
                  dig(row, "asset_name") as? String == nightName else { continue }
            let q = Double(dig(row, "quantity") as? String ?? "") ?? 0
            let dec = num(dig(row, "decimals")) ?? 6
            night += q / pow(10, dec)
        }
        return CardanoBal(ada: lovelace / 1e6, night: night)
    }

    // MARK: 시세 (원화)

    static func prices(on: Bool = true) async -> [String: Quote]? {
        guard on else { return nil }
        let ids = Set(geckoIds.values).sorted().joined(separator: ",")
        guard let j = try? await get(gecko + "simple/price?ids=\(ids)&vs_currencies=krw&include_24hr_change=true") else { return nil }
        var out: [String: Quote] = [:]
        for (app, g) in geckoIds {
            if let krw = num(dig(j, g, "krw")) {
                out[app] = Quote(krw: krw, change: num(dig(j, g, "krw_24h_change")) ?? 0)
            }
        }
        return out.isEmpty ? nil : out
    }

    /// 기간별 가격 (시간, 원화)
    static func chart(_ app: String, days: String) async -> [(Date, Double)]? {
        guard let g = geckoIds[app],
              let j = try? await get(gecko + "coins/\(g)/market_chart?vs_currency=krw&days=\(days)"),
              let rows = dig(j, "prices") as? [Any] else { return nil }
        let pts: [(Date, Double)] = rows.compactMap { r in
            guard let a = r as? [Any], a.count >= 2, let t = num(a[0]), let p = num(a[1]) else { return nil }
            return (Date(timeIntervalSince1970: t / 1000), p)
        }
        return pts.count >= 2 ? pts : nil
    }

    // MARK: 통신 도우미

    struct HTTPError: Error { let code: Int }

    /// 읽기 전용 요청. 429·5xx·네트워크 끊김이면 잠깐 쉬었다가 한 번 더 시도하고, 실패 이유는 로그로 남김
    private static func send(_ r: URLRequest) async throws -> Any {
        var last: Error = HTTPError(code: 0)
        for attempt in 1...2 {
            do {
                let (d, resp) = try await URLSession.shared.data(for: r)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else { throw HTTPError(code: code) }
                return try JSONSerialization.jsonObject(with: d)
            } catch {
                last = error
                print("[잔액] \(r.url?.host ?? "?") 실패 (\(attempt)/2): \(error)")
                let retryable: Bool
                if let h = error as? HTTPError { retryable = h.code == 429 || h.code >= 500 }
                else if let u = error as? URLError { retryable = u.code != .cancelled }
                else { retryable = false }
                if !retryable || attempt == 2 { break }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        throw last
    }

    private static func get(_ s: String) async throws -> Any {
        guard let u = URL(string: s) else { throw HTTPError(code: -1) }
        var r = URLRequest(url: u, timeoutInterval: 15)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(r)
    }

    private static func post(_ u: URL, _ body: Any) async throws -> Any {
        var r = URLRequest(url: u, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(r)
    }

    private static func rpc(_ u: URL, _ method: String, _ params: [Any]) async throws -> Any {
        let j = try await post(u, ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        if dig(j, "error") != nil { throw HTTPError(code: -2) }
        guard let r = dig(j, "result") else { throw HTTPError(code: -3) }
        return r
    }

    /// JSON 안쪽으로 들어가기: dig(j, "a", "b")
    static func dig(_ o: Any?, _ keys: String...) -> Any? {
        var cur = o
        for k in keys {
            guard let d = cur as? [String: Any], let next = d[k], !(next is NSNull) else { return nil }
            cur = next
        }
        return cur
    }

    static func num(_ o: Any?) -> Double? {
        if let n = o as? NSNumber { return n.doubleValue }
        if let s = o as? String { return Double(s) }
        return nil
    }

    /// "0x1bc16d674ec80000" → 2e18 (UInt64 를 넘는 값도 처리)
    static func hexToDouble(_ hex: String) -> Double? {
        let h = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        if h.isEmpty { return 0 }
        var v = 0.0
        for c in h {
            guard let d = c.hexDigitValue else { return nil }
            v = v * 16 + Double(d)
        }
        return v
    }
}
