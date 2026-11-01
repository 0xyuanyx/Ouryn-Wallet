import SwiftUI

// TxRow.js, AssetRow.js, CountUp.js, SoonRow.js, Screen.js, Metal.js(Sheen)

// MARK: - 거래 한 줄

struct TxMeta {
    var title: String
    var avatar: AvatarSpec
    var sign: Int
    var verb: String
}

func txMeta(_ st: AppState, _ t: Tx) -> TxMeta {
    let n = st.nameOf(t.addr,net:t.network)
    // 내 통장과 주고받은 거래 (사용자가 붙인 이름이 없을 때) → 로고 아바타
    if let a = t.addr, let own = st.ownAccount(address: a, net: t.network), n == own.title, t.type == .send || t.type == .receive {
        return TxMeta(title: own.title, avatar: AvatarSpec(logo: true), sign: t.type == .send ? -1 : 1, verb: t.type == .send ? "보냄" : "받음")
    }
    switch t.type {
    case .receive:
        if n == nil, let via = t.via {
            return TxMeta(title: via, avatar: AvatarSpec(icon: "business", color: C.surface3), sign: 1, verb: "거래소에서 가져옴")
        }
        // 잔액이 늘어난 걸 보고 만든 입금 — 보낸 주소 자체를 모름
        if t.addr == nil && t.via == nil {
            return TxMeta(title: "보낸 곳을 몰라요", avatar: AvatarSpec(icon: "help", color: C.surface3), sign: 1, verb: "받음")
        }
        return TxMeta(title: n ?? "모르는 지갑", avatar: n != nil ? AvatarSpec(name: n) : AvatarSpec(icon: "help", color: C.surface3), sign: 1, verb: "받음")
    case .send:
        return TxMeta(title: n ?? "모르는 지갑", avatar: n != nil ? AvatarSpec(name: n) : AvatarSpec(icon: "help", color: C.surface3), sign: -1, verb: "보냄")
    case .interest:
        return TxMeta(title: "이자", avatar: AvatarSpec(icon: "leaf", color: C.greenSoft, iconColor: C.green), sign: 1, verb: "이자 모으기")
    case .save:
        return TxMeta(title: "이자 모으기로 옮김", avatar: AvatarSpec(icon: "arrow-forward", color: C.surface3, iconColor: C.sub), sign: 0, verb: "내 돈 이동")
    case .unsave:
        return TxMeta(title: "이자 모으기에서 꺼냄", avatar: AvatarSpec(icon: "arrow-back", color: C.surface3, iconColor: C.sub), sign: 0, verb: "내 돈 이동")
    }
}

/// 거래 상태 글자·색 (완료는 nil)
func txStatusLabel(_ t: Tx) -> (String, Color, Color)? {
    switch t.status {
    case .pending: return (t.type == .receive ? "오는 중" : "확인 중", C.amber, C.amberSoft)
    case .delayed: return ("늦어지는 중", C.amber, C.amberSoft)
    case .failed: return (t.type == .receive ? "도착 안 함" : "실패", C.red, C.redSoft)
    case .done: return nil
    }
}

struct TxRow: View {
    @EnvironmentObject var store: Store
    let t: Tx
    var showTime = true
    var onPress: (() -> Void)? = nil

    var body: some View {
        let st = store.st
        let m = txMeta(st, t)
        let unknown = t.addr != nil && st.nameOf(t.addr,net:t.network) == nil
        let mine: OwnAccount? = t.addr.flatMap { a in st.ownAccount(address: a, net: t.network).flatMap { o in st.nameOf(a, net: t.network) == o.title ? o : nil } }
        let settled = t.status == .done
        let sign = !settled ? "" : (m.sign > 0 ? "+" : (m.sign < 0 ? "-" : ""))
        let amount = st.hide ? "••••" : (t.inFlight && t.amt == 0 ? "—" : sign + (st.unit == "krw" ? wonOf(t.amt) : dollar(t.amt)))
        var parts: [String] = []
        if showTime { parts.append(timeLabel(t.ts)) }
        if !t.memo.isEmpty { parts.append(t.memo) } else if m.sign == 0 || t.type == .interest { parts.append(m.verb) }
        // 오른쪽 아래: 진행 상태 > 코인 수량
        let status = txStatusLabel(t)
        let coinQty = (!t.isDollar && !st.hide) ? "\(assetMeta(t.assetId).name) \(qtyText(t.quantity))" : nil
        var tag: AnyView? = nil
        if unknown { tag = AnyView(Chip(label: "이름 붙이기", soon: true)) }
        else if let o = mine { tag = AnyView(MineTag(text: st.mineTagText(o))) }
        return ListItem(
            left: AnyView(m.avatar.view()),
            title: m.title,
            titleRight: tag,
            sub: parts.joined(separator: " · "),
            right: amount,
            rightSub: status?.0 ?? coinQty,
            rightSubColor: status?.1,
            rightColor: !settled ? C.mute : (m.sign > 0 ? C.green : (m.sign == 0 ? C.sub : C.text)),
            onPress: onPress
        )
    }
}

// MARK: - 자산 한 줄

struct AssetBadge: View {
    let badge: Badge
    var size: CGFloat = 44
    /// 코인 id (usdc, trx …) — 로고 이미지가 있으면 로고로
    var asset: String? = nil
    /// 네트워크 이름 — 주면 오른쪽 아래에 작은 네트워크 로고
    var network: String? = nil

    var body: some View {
        if CoinArt.asset(asset) != nil {
            CoinLogo(asset: asset, network: network, size: size)
        } else {
            fallback
        }
    }

    @ViewBuilder private var fallback: some View {
        switch badge {
        case .green(let icon):
            ZStack {
                Circle().fill(C.greenSoft)
                Icon(icon, size * 0.45, C.green)
            }
            .frame(width: size, height: size)
        case .icon(let icon):
            MetalBadge(icon: icon, size: size)
        case .label(let l):
            MetalBadge(label: l, size: size)
        }
    }
}

// 지갑 한 줄: 이름 / 수량 · 원화 가치 / (코인이면) 등락률
struct AssetRow: View {
    @EnvironmentObject var store: Store
    let id: String
    var rightNode: AnyView? = nil
    var dim = false
    var onPress: (() -> Void)? = nil

    var body: some View {
        let st = store.st
        let a = assetLine(st, id)
        let value = st.hide ? "••••" : (st.unit == "krw" ? won(a.krw) : dollar(a.usd))
        let ch = a.change
        return ListItem(
            left: AnyView(AssetBadge(badge: a.badge, asset: id)),
            title: a.name,
            sub: st.hide ? nil : a.sub,
            right: rightNode != nil ? nil : value,
            rightSub: rightNode == nil && ch != nil ? pct(ch ?? 0) : nil,
            rightSubColor: (ch ?? 0) > 0 ? C.up : ((ch ?? 0) < 0 ? C.down : nil),
            rightNode: rightNode,
            dim: dim,
            onPress: onPress
        )
    }
}

// MARK: - 숫자가 부드럽게 올라가는 글자

struct CountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String
    var w: W = .b
    var size: CGFloat = 36
    var color: Color = C.text
    var tracking: CGFloat = -1.2

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        TX(format(value), w, size, color, lines: 1, tracking: tracking)
    }
}

struct CountUp: View {
    let value: Double
    let format: (Double) -> String
    var w: W = .b
    var size: CGFloat = 36
    var tracking: CGFloat = -1.2

    @State private var shown: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CountingText(value: shown ?? value, format: format, w: w, size: size, tracking: tracking)
            .onChange(of: value) { old, new in
                if reduceMotion { shown = new; return }
                if shown == nil { shown = old }
                withAnimation(Ease.outCubic(0.7)) { shown = new }
            }
    }
}

// MARK: - 곧 지원할 돈 (원화·엔화)

struct SoonRow: View {
    let symbol: String
    let title: String
    let sub: String
    let on: Bool
    let onToggle: () -> Void

    var body: some View {
        ListItem(
            left: AnyView(
                ZStack {
                    Circle().fill(C.surface2)
                    Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    TX(symbol, .b, 18, C.mute)
                }
                .frame(width: 44, height: 44)
            ),
            title: title,
            titleRight: AnyView(Chip(label: "준비 중", soon: true)),
            sub: sub,
            rightNode: AnyView(
                HStack(spacing: 4) {
                    Icon(on ? "notifications" : "notifications-outline", 14, on ? C.blueText : C.sub)
                    TX(on ? "알림 켜짐" : "알림 받기", .sb, 13, on ? C.blueText : C.sub)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Capsule().fill(on ? C.blueSoft : C.surface2))
            ),
            onPress: onToggle
        )
    }
}

// MARK: - 기본 화면: 스크롤 + 하단 고정 버튼

struct OScreen<Content: View, Footer: View>: View {
    var pad: CGFloat = 20
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(pad)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            if Footer.self != EmptyView.self {
                footer()
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, Insets.footerExtra)
            }
        }
        .background(C.bg.ignoresSafeArea())
    }
}

extension OScreen where Footer == EmptyView {
    init(pad: CGFloat = 20, @ViewBuilder content: @escaping () -> Content) {
        self.init(pad: pad, content: content, footer: { EmptyView() })
    }
}

// MARK: - 빛이 한 번씩 스쳐 지나가는 효과

struct Sheen: View {
    var every: Double = 4.2
    var width: CGFloat = 70
    var opacity: Double = 0.22

    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                let period = 1.1 + every
                let t = tl.date.timeIntervalSince(start).truncatingRemainder(dividingBy: period)
                let k = t < 1.1 ? Curve.inOutCubic(t / 1.1) : 1
                let x = -width * 2 + (geo.size.width + width * 3) * k
                LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(opacity), Color.white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: width, height: geo.size.height + 80)
                    .rotationEffect(.degrees(18))
                    .position(x: x + width / 2, y: geo.size.height / 2)
            }
        }
        .allowsHitTesting(false)
        .clipped()
    }
}
