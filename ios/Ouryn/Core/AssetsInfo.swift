import Foundation

// 홈에 나열되는 지갑(자산). 종류는 고정, 순서만 사용자가 편집
// 솔라나(SOL)·에이다(ADA)는 각 네트워크 수수료로 쓰이는 코인이라 함께 보여줌

let ASSET_IDS = ["usdc", "usdt", "savings", "sol", "eth", "btc", "ada", "night", "trx", "mnt", "avax", "usdt0"]

enum Badge: Equatable {
    case label(String)
    case icon(String)
    case green(String)
}

struct AssetMeta {
    let name: String
    let sub: String?
    let badge: Badge
    let coin: Bool
}

let ASSETS: [String: AssetMeta] = [
    "usdc": AssetMeta(name: "달러", sub: "서클 달러", badge: .label("$"), coin: false),
    "usdt": AssetMeta(name: "달러", sub: "테더 달러", badge: .label("$"), coin: false),
    "savings": AssetMeta(name: "이자 모으기", sub: nil, badge: .green("leaf"), coin: false),
    "usdt0": AssetMeta(name:"USDT0", sub:"맨틀 · USDT0", badge:.label("$"), coin:true),
    "trx": AssetMeta(name: "트론", sub: "TRX", badge: .label("T"), coin: true),
    "mnt": AssetMeta(name: "맨틀", sub: "MNT", badge: .label("M"), coin: true),
    "avax": AssetMeta(name: "아발란체", sub: "C-Chain · AVAX", badge: .label("A"), coin: true),
    "sol": AssetMeta(name: "솔라나", sub: nil, badge: .label("◎"), coin: true),
    "eth": AssetMeta(name: "이더리움", sub: nil, badge: .label("Ξ"), coin: true),
    "ada": AssetMeta(name: "에이다", sub: "카르다노", badge: .label("₳"), coin: true),
    "btc": AssetMeta(name: "비트코인", sub: nil, badge: .label("₿"), coin: true),
    "night": AssetMeta(name: "나이트", sub: "미드나이트", badge: .icon("moon"), coin: true),
]

func assetMeta(_ id: String) -> AssetMeta { ASSETS[id] ?? AssetMeta(name: id, sub: nil, badge: .label("?"), coin: false) }

/// 자산을 눌렀을 때 갈 화면
func assetRoute(_ id: String) -> Route {
    switch id {
    case "usdc", "usdt": return .dollar
    case "savings": return .savings
    default: return .coin(id)
    }
}

struct AssetLine {
    let name: String
    let sub: String
    let badge: Badge
    let usd: Double
    let krw: Double
    let change: Double?
}

// 한 줄에 필요한 값들
func assetLine(_ st: AppState, _ id: String) -> AssetLine {
    let a = assetMeta(id)
    if id == "usdc" || id == "usdt" {
        let n = id == "usdc" ? st.wallet.circle : st.wallet.tether
        return AssetLine(name: a.name, sub: "\(a.sub ?? "") · \(dollar(n))", badge: a.badge, usd: n, krw: n * RATE, change: nil)
    }
    if id == "savings" {
        return AssetLine(name: a.name, sub: "준비 중이에요", badge: a.badge,
                         usd: st.savings.principal, krw: st.savings.principal * RATE, change: nil)
    }
    let k = st.coinKrw(id)
    let sub = (a.sub.map { $0 + " · " } ?? "") + qtyText(st.coins[id] ?? 0)
    return AssetLine(name: a.name, sub: sub, badge: a.badge, usd: k / RATE, krw: k, change: st.change[id])
}
