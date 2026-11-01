import Foundation

// 테스트 통장 = 테스트넷에서 쓰는 통장. 실제 돈이 아닌 테스트 토큰으로 받기·보내기를 연습
// 지금 통장이 테스트 통장이면 Store.applySlot 이 Testnet.on 을 켜고, 서버 주소·토큰 주소·탐색기가 모두 테스트넷으로 바뀜
//   솔라나   devnet        api.devnet.solana.com         USDC 4zMMC9…ncDU (Circle)
//   이더리움 Sepolia       ethereum-sepolia-rpc.publicnode.com  USDC 0x1c7D…7238 (Circle)
//   Avalanche Fuji         api.avax-test.network          USDC 0x5425…Bc65 (Circle)
//   맨틀     Sepolia       rpc.sepolia.mantle.xyz
//   트론     Nile          nile.trongrid.io               USDT TXYZ…kAeBf
//   비트코인 testnet4      mempool.space/testnet4         주소 tb1… (m/84'/1'/n'/0/0)
//   카르다노 preprod       preprod.koios.rest             주소 addr_test1…

enum Testnet {
    /// 지금 통장이 테스트 통장인지 (Store.applySlot 이 맞춤)
    static var on = false

    static let bitcoinGenesis = "00000000da84f2bafbbc53dee25a72ae507ff4914b867c565be350b0da8bf043" // testnet4
    static let solanaGenesis = "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG" // devnet

    /// 테스트넷 이름
    static func name(_ n: WalletNetwork) -> String {
        switch n {
        case .solana: return "솔라나 Devnet"
        case .ethereum: return "이더리움 Sepolia"
        case .mantle: return "맨틀 Sepolia"
        case .avalanche: return "Avalanche Fuji"
        case .tron: return "트론 Nile"
        case .bitcoin: return "비트코인 Testnet4"
        case .cardano: return "카르다노 Preprod"
        }
    }

    struct Faucet: Identifiable {
        let label: String
        let url: URL?          // nil = 앱 안에서 바로 받기 (솔라나 에어드롭)
        var id: String { label }
    }

    static let circle = URL(string: "https://faucet.circle.com/")

    /// 네트워크별 테스트 토큰 받는 곳
    static func faucets(_ n: WalletNetwork) -> [Faucet] {
        switch n {
        case .solana: return [Faucet(label: "1 SOL 받기", url: nil), Faucet(label: "SOL", url: URL(string: "https://faucet.solana.com/")), Faucet(label: "USDC", url: circle)]
        case .ethereum: return [Faucet(label: "ETH", url: URL(string: "https://cloud.google.com/application/web3/faucet/ethereum/sepolia")), Faucet(label: "USDC", url: circle)]
        case .avalanche: return [Faucet(label: "AVAX", url: URL(string: "https://core.app/tools/testnet-faucet/?subnet=c&token=c")), Faucet(label: "USDC", url: circle)]
        case .mantle: return [Faucet(label: "MNT", url: URL(string: "https://faucet.sepolia.mantle.xyz/"))]
        case .tron: return [Faucet(label: "TRX · USDT", url: URL(string: "https://nileex.io/join/getJoinPage"))]
        case .bitcoin: return [Faucet(label: "BTC", url: URL(string: "https://mempool.space/testnet4/faucet"))]
        case .cardano: return [Faucet(label: "ADA", url: URL(string: "https://docs.cardano.org/cardano-testnets/tools/faucet"))]
        }
    }

    /// 솔라나 devnet 에어드롭 (1 SOL). 성공하면 거래 해시
    /// 공용 devnet 서버는 에어드롭을 IP 당 아주 조금만 허용 → 막히면 사이트(faucet.solana.com)로 안내
    static func airdrop(_ address: String) async throws -> String {
        guard on else { throw TransferError.invalid("테스트 통장에서만 받을 수 있어요") }
        var r = URLRequest(url: ChainAPI.solanaRPC); r.httpMethod = "POST"; r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "requestAirdrop", "params": [address, 1_000_000_000]])
        let result: (Data, URLResponse)
        do { result = try await URLSession.shared.data(for: r) }
        catch { throw TransferError.invalid("devnet 서버에 연결하지 못했어요 · 인터넷 연결을 확인해주세요") }
        let code = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any]
        if let sig = json?["result"] as? String, (200..<300).contains(code) { return sig }
        let reason = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
        if code == 429 || reason.lowercased().contains("limit") || reason.lowercased().contains("dry") {
            throw TransferError.invalid("devnet 에어드롭 한도에 걸렸어요 · 옆 'SOL' 사이트에서 받아주세요")
        }
        let detail = reason.isEmpty ? "" : " · " + String(reason.prefix(60))
        throw TransferError.invalid("devnet 에어드롭 실패 (\(code))" + detail)
    }

    // MARK: QR · 주소로 테스트넷 알아보기

    /// 주소 모양만으로 테스트넷 (비트코인 tb1… · 카르다노 addr_test1…)
    static func looksTest(_ a: String) -> Bool {
        let s = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s.hasPrefix("tb1") || s.hasPrefix("addr_test1")
    }
    /// 주소 모양만으로 실제 네트워크 (비트코인 bc1… · 카르다노 addr1…). 솔라나·0x·트론 주소는 둘 다 같은 모양이라 알 수 없음
    static func looksMain(_ a: String) -> Bool {
        let s = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s.hasPrefix("bc1") || s.hasPrefix("addr1")
    }

    /// Ouryn QR 의 네트워크 짧은 이름
    static func code(_ n: WalletNetwork) -> String {
        switch n {
        case .solana: return "sol"
        case .ethereum: return "eth"
        case .mantle: return "mnt"
        case .avalanche: return "avax"
        case .tron: return "trx"
        case .bitcoin: return "btc"
        case .cardano: return "ada"
        }
    }
    static func network(code: String) -> WalletNetwork? { WalletNetwork.allCases.first { self.code($0) == code } }

    /// 테스트 통장의 받기 QR — "ouryn:<주소>?n=eth&x=t" (x=t: 테스트넷)
    static func payload(to: String, network: WalletNetwork) -> String { "ouryn:\(to)?n=\(code(network))&x=t" }

    /// EIP-681 체인 번호 → 네트워크 · 테스트넷 여부
    static func evm(chain: Int) -> (WalletNetwork, Bool)? {
        switch chain {
        case 1: return (.ethereum, false)
        case 5000: return (.mantle, false)
        case 43114: return (.avalanche, false)
        case 11155111: return (.ethereum, true)
        case 5003: return (.mantle, true)
        case 43113: return (.avalanche, true)
        default: return nil
        }
    }

    // MARK: 주소 바꾸기 (같은 키 · 다른 네트워크 표기)

    /// 비트코인: tb1… → bc1… (스크립트가 같아서 Wallet Core 서명에는 bc1 표기를 씀)
    static func btcCore(_ a: String) -> String {
        guard a.lowercased().hasPrefix("tb1"), let d = Bech32Lite.decode(a) else { return a }
        return Bech32Lite.encode("bc", d.data)
    }
    /// 비트코인: bc1… → tb1…
    static func btcTest(_ a: String) -> String {
        guard let d = Bech32Lite.decode(a) else { return a }
        return Bech32Lite.encode("tb", d.data)
    }
    /// 카르다노: addr1… → addr_test1… (머리 바이트의 네트워크 번호 1 → 0)
    static func cardanoTest(_ a: String) -> String {
        guard var bytes = cardanoBytes(a), !bytes.isEmpty else { return a }
        bytes[0] = bytes[0] & 0xF0
        guard let five = Bech32Lite.convert([UInt8](bytes), from: 8, to: 5, pad: true) else { return a }
        return Bech32Lite.encode("addr_test", five)
    }
    /// 카르다노 주소 원문 바이트 (머리 + 키 해시)
    static func cardanoBytes(_ a: String) -> Data? {
        guard let d = Bech32Lite.decode(a), let bytes = Bech32Lite.convert(d.data, from: 5, to: 8, pad: false) else { return nil }
        return Data(bytes)
    }
}

/// BIP-173 bech32 (카르다노 주소처럼 90자를 넘는 것도 처리)
enum Bech32Lite {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(v)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 { chk ^= gen[i] }
        }
        return chk
    }

    private static func expand(_ hrp: String) -> [UInt8] {
        let b = Array(hrp.utf8)
        return b.map { $0 >> 5 } + [0] + b.map { $0 & 31 }
    }

    static func decode(_ s: String) -> (hrp: String, data: [UInt8])? {
        let lower = s.lowercased()
        guard lower == s || s.uppercased() == s, let pos = lower.lastIndex(of: "1") else { return nil }
        let hrp = String(lower[..<pos])
        let rest = lower[lower.index(after: pos)...]
        guard !hrp.isEmpty, rest.count >= 6 else { return nil }
        var data: [UInt8] = []
        for c in rest {
            guard let i = charset.firstIndex(of: c) else { return nil }
            data.append(UInt8(i))
        }
        guard polymod(expand(hrp) + data) == 1 else { return nil }
        return (hrp, Array(data.dropLast(6)))
    }

    static func encode(_ hrp: String, _ data: [UInt8]) -> String {
        let mod = polymod(expand(hrp) + data + [0, 0, 0, 0, 0, 0]) ^ 1
        let checksum = (0..<6).map { UInt8((mod >> UInt32(5 * (5 - $0))) & 31) }
        return hrp + "1" + String((data + checksum).map { charset[Int($0)] })
    }

    static func convert(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var acc = 0, bits = 0
        var out: [UInt8] = []
        let maxv = (1 << to) - 1
        let maxAcc = (1 << (from + to - 1)) - 1
        for v in data {
            guard Int(v) >> from == 0 else { return nil }
            acc = ((acc << from) | Int(v)) & maxAcc
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits > 0 { out.append(UInt8((acc << (to - bits)) & maxv)) }
        } else if bits >= from || ((acc << (to - bits)) & maxv) != 0 {
            return nil
        }
        return out
    }
}
