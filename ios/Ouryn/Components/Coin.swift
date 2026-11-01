import SwiftUI

// MARK: - 코인·네트워크 로고 (Assets.xcassets 의 coin-*)

enum CoinArt {
    static func asset(_ a: String?) -> String? {
        guard let a else { return nil }
        switch a {
        case "usdt", "usdt0": return "coin-usdt"
        case "usdc": return "coin-usdc"
        case "trx", "sol", "eth", "btc", "ada", "avax", "mnt", "night": return "coin-" + a
        default: return nil
        }
    }

    static func network(_ n: String?) -> String? {
        guard let n else { return nil }
        switch n {
        case "트론": return "coin-trx"
        case "솔라나": return "coin-sol"
        case "이더리움": return "coin-eth"
        case "맨틀": return "coin-mnt"
        case "Avalanche C-Chain": return "coin-avax"
        case "비트코인": return "coin-btc"
        case "카르다노": return "coin-ada"
        default: return nil
        }
    }
}

/// 코인 로고 + 오른쪽 아래 작은 네트워크 로고 (예: USDT + 트론)
/// asset 이 없으면 네트워크 로고만, 둘 다 모르면 지갑 아이콘
struct CoinLogo: View {
    var asset: String? = nil
    var network: String? = nil
    var size: CGFloat = 40
    /// 작은 로고 테두리 = 놓인 바탕색
    var ring: Color = C.bg

    var body: some View {
        let main = CoinArt.asset(asset) ?? CoinArt.network(network)
        let net = CoinArt.network(network)
        let badge: String? = (CoinArt.asset(asset) != nil && net != main) ? net : nil
        ZStack(alignment: .bottomTrailing) {
            if let main {
                Image(main).resizable().scaledToFit().frame(width: size, height: size)
            } else {
                Circle().fill(C.surface3).frame(width: size, height: size)
                    .overlay(Icon("wallet-outline", size * 0.45, C.text))
            }
            if let badge {
                let b = max(14, size * 0.42)
                Image(badge).resizable().scaledToFit().frame(width: b, height: b)
                    .background(Circle().fill(ring).padding(-max(2, size * 0.05)))
                    .offset(x: size * 0.1, y: size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension View {
    /// 이름 동그라미 오른쪽 아래에 네트워크 로고
    func networkBadge(_ network: String?, size: CGFloat, ring: Color = C.bg) -> some View {
        overlay(alignment: .bottomTrailing) {
            if let n = CoinArt.network(network) {
                let b = max(14, size * 0.42)
                Image(n).resizable().scaledToFit().frame(width: b, height: b)
                    .background(Circle().fill(ring).padding(-2))
                    .offset(x: size * 0.08, y: size * 0.08)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - 주소: 앞 6 · 뒤 6 자리 강조

/// full = 전체 주소(가운데는 흐리게), 아니면 "앞6 ··· 뒤6"
func addrText(_ a: String, full: Bool = false, size: CGFloat = 15, base: Color = C.sub, w: W = .r) -> Text {
    let s = a.trimmingCharacters(in: .whitespacesAndNewlines)
    guard s.count > 14 else { return tt(s, w, size, base) }
    let head = String(s.prefix(6)), tail = String(s.suffix(6))
    let mid = full ? String(s.dropFirst(6).dropLast(6)) : " ··· "
    return tt(head, .sb, size, C.addr) + tt(mid, w, size, base) + tt(tail, .sb, size, C.addr)
}

struct AddrText: View {
    let addr: String
    var full = false
    var size: CGFloat = 15
    var base: Color = C.sub

    var body: some View {
        addrText(addr, full: full, size: size, base: base)
            .lineLimit(full ? nil : 1)
            .fixedSize(horizontal: false, vertical: full)
    }
}

// MARK: - 지갑 주소 입력칸
/// 입력 중엔 전체 한 줄(옆으로 넘김), 입력이 끝나면 "앞6 ··· 뒤6"
/// 오른쪽: 내용 지우기 ⓧ · QR 찍기(카메라)

struct AddressField: View {
    @Binding var text: String
    var placeholder = "지갑 주소를 입력하세요"
    var onScan: (() -> Void)? = nil

    @FocusState private var focus: Bool
    private var compact: Bool { !focus && text.count > 16 }

    var body: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    TX(placeholder, .m, 16, C.mute, lines: 1).allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .font(pfont(.m, 16))
                    .foregroundColor(C.text)
                    .tint(C.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .focused($focus)
                    .opacity(compact ? 0 : 1)
                if compact {
                    AddrText(addr: text, size: 16, base: C.mute).allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { focus = true }

            if !text.isEmpty {
                Button { text = ""; focus = true } label: {
                    Icon("close-circle", 20, C.mute).frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("주소 지우기")
            }
            if let onScan {
                Tap(action: { focus = false; onScan() }) {
                    Icon("camera-outline", 20, C.text)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(C.surface3))
                }
                .accessibilityLabel("QR 찍기")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(focus ? C.faint : C.line, lineWidth: 1))
    }
}

extension WalletNetwork {
    /// 주소 모양으로 네트워크 찾기. 0x 주소는 이더리움·맨틀·Avalanche 셋 다 나옴
    static func detect(_ raw: String) -> [WalletNetwork] {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 20 else { return [] }
        return allCases.filter { WalletKeys.valid(s, network: $0) }
    }
    var isEVM: Bool { self == .ethereum || self == .mantle || self == .avalanche }
}

// MARK: - 코인 → 네트워크 고르기 (보내기·받기 공용)

/// 네트워크 + 실제 자산 id (맨틀 USDT = usdt0)
struct TokenItem: Identifiable, Hashable {
    let network: WalletNetwork
    let asset: String
    var id: String { network.rawValue + "|" + asset }
}

struct TokenChoice: Identifiable {
    let token: String
    let items: [TokenItem]
    var id: String { token }
}

enum TokenCatalog {
    static let order = ["usdt", "usdc", "trx", "sol", "eth", "btc", "ada", "night", "mnt", "avax"]

    /// 같은 코인으로 묶는 id (usdt0 → usdt)
    static func token(of asset: String) -> String { asset == "usdt0" ? "usdt" : asset }

    static var choices: [TokenChoice] {
        let all = WalletNetwork.allCases.flatMap { n in n.assets.map { TokenItem(network: n, asset: $0) } }
        return order.compactMap { t in
            let items = all.filter { token(of: $0.asset) == t }
            return items.isEmpty ? nil : TokenChoice(token: t, items: items)
        }
    }

    /// (이름, 기호) — 달러 둘은 '테더 달러'처럼
    static func label(_ t: String) -> (name: String, symbol: String) {
        let m = assetMeta(t)
        if t == "usdc" || t == "usdt" { return (m.sub ?? m.name, t.uppercased()) }
        return (m.name, t.uppercased())
    }
}

struct TokenNetworkPicker: View {
    /// 고른 코인 (nil = 코인 목록)
    @Binding var token: String?
    var title: String
    var sub: String? = nil
    var networkTitle: String
    var networkSub: String
    var current: TokenItem? = nil
    /// 주면 네트워크마다 내 주소를 보여주고, 주소가 없으면 막음
    var addressOf: ((WalletNetwork) -> String?)? = nil
    var showBack = true
    var ground: Color = C.bg
    let onPick: (TokenItem) -> Void

    var body: some View {
        if let t = token, let c = TokenCatalog.choices.first(where: { $0.token == t }) {
            networks(c)
        } else {
            tokens
        }
    }

    private var tokens: some View {
        VStack(alignment: .leading, spacing: 0) {
            TX(title, .b, 24)
            if let sub { TX(sub, .r, 15, C.sub, lh: 22).padding(.top, 8) }
            VStack(spacing: 8) {
                ForEach(TokenCatalog.choices) { c in
                    let l = TokenCatalog.label(c.token)
                    let on = current.map { TokenCatalog.token(of: $0.asset) == c.token } ?? false
                    Tap(scale: 0.98, action: {
                        haptic(.select)
                        if c.items.count == 1 { onPick(c.items[0]) } else { token = c.token }
                    }) {
                        HStack(spacing: 14) {
                            CoinLogo(asset: c.token, size: 42, ring: C.surface)
                            VStack(alignment: .leading, spacing: 5) {
                                tt(l.name, .sb, 16) + tt("  " + l.symbol, .r, 14, C.mute)
                                HStack(spacing: 6) {
                                    HStack(spacing: -5) {
                                        ForEach(c.items) { it in
                                            CoinLogo(network: it.network.rawValue, size: 16)
                                                .background(Circle().fill(on ? C.surface2 : C.surface).padding(-1.5))
                                        }
                                    }
                                    TX(c.items.count == 1 ? "\(c.items[0].network.rawValue) 네트워크"
                                       : "\(c.items[0].network.rawValue) 외 \(c.items.count - 1)개 네트워크", .r, 12, C.mute, lines: 1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if c.items.count > 1 { Icon("chevron-forward", 18, C.mute) }
                            else if on { Icon("checkmark", 20, C.text) }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(on ? C.surface2 : C.surface))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? C.faint : .clear, lineWidth: 1))
                    }
                }
            }
            .padding(.top, 20)
        }
    }

    private func networks(_ c: TokenChoice) -> some View {
        let l = TokenCatalog.label(c.token)
        return VStack(alignment: .leading, spacing: 0) {
            if showBack {
                Tap(action: { token = nil }) {
                    HStack(spacing: 4) { Icon("chevron-back", 16, C.sub); TX("다른 코인", .m, 14, C.sub) }
                        .frame(minHeight: 36)
                }
            }
            HStack(spacing: 8) {
                CoinLogo(asset: c.token, size: 24, ring: ground)
                TX("\(l.name) · \(l.symbol)", .sb, 14, C.sub)
            }
            .padding(.top, showBack ? 8 : 0)
            TX(networkTitle, .b, 24).padding(.top, 12)
            TX(networkSub, .r, 14, C.sub, lh: 21).padding(.top, 8)
            VStack(spacing: 8) {
                ForEach(c.items) { it in
                    let a = addressOf?(it.network)
                    let blocked = addressOf != nil && a == nil
                    let on = current == it
                    Tap(scale: 0.98, disabled: blocked, action: { haptic(.select); onPick(it) }) {
                        HStack(spacing: 14) {
                            CoinLogo(network: it.network.rawValue, size: 40, ring: C.surface)
                            VStack(alignment: .leading, spacing: 3) {
                                TX("\(it.network.rawValue) 네트워크" + (it.asset == "usdt0" ? " · USDT0" : ""), .sb, 16)
                                if blocked {
                                    TX("주소 검사를 통과하지 못해 잠시 막아뒀어요", .r, 13, C.red)
                                } else if let a {
                                    AddrText(addr: a, size: 13, base: C.mute)
                                } else {
                                    TX("수수료는 \(it.network.native.uppercased())로 내요", .r, 13, C.mute)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if on { Icon("checkmark", 20, C.text) } else { Icon("chevron-forward", 18, C.mute) }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(on ? C.surface2 : C.surface))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? C.faint : .clear, lineWidth: 1))
                        .opacity(blocked ? 0.5 : 1)
                    }
                }
            }
            .padding(.top, 20)
        }
    }
}
