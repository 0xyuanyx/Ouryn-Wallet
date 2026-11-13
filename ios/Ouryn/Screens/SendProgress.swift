import SwiftUI

/// 보낸 뒤 화면. 보낸 거래(Tx)의 상태를 그대로 따라감:
/// 보내는 중(네트워크에 올리는 중) → 가는 중(처리 대기) → 보냈어요 / 늦어지는 중 / 보내지 못했어요
struct SendProgressView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let quote: TransferQuote
    let hash: String
    /// 전파 응답을 못 받음 — 갔을 수도 있으니 다시 보내면 안 됨
    let uncertain: Bool

    enum Phase: Equatable { case sending, moving, delayed, done, failed }

    private var txId: String { quote.network.rawValue + hash }
    private var tx: Tx? { store.st.tx.first { $0.id == txId } }
    private var phase: Phase {
        guard let t = tx else { return .sending }
        switch t.status {
        case .done: return .done
        case .failed: return .failed
        case .delayed: return .delayed
        case .pending: return t.via == "전파 완료" || uncertain ? .moving : .sending
        }
    }
    private var inFlight: Bool { phase == .sending || phase == .moving || phase == .delayed }
    private var netName: String { Testnet.on ? Testnet.name(quote.network) : quote.network.rawValue }
    private var own: OwnAccount? { store.st.ownAccount(address: quote.recipient, net: quote.network.rawValue) }
    private var who: String? { store.st.nameOf(quote.recipient, net: quote.network.rawValue) }
    private var qty: Decimal { ExactAmount.display(raw: quote.raw, decimals: quote.network.decimals(quote.asset)) }
    private var won: Double { NSDecimalNumber(decimal: qty).doubleValue * store.st.usdPrice(quote.asset) }

    /// 네트워크별로 보통 걸리는 시간
    private var eta: String {
        switch quote.network {
        case .solana, .tron, .mantle, .avalanche: return "보통 몇 초면 끝나요"
        case .ethereum: return "보통 1분 안에 끝나요"
        case .cardano: return "보통 1~2분 걸려요"
        case .bitcoin: return "보통 10~30분 걸려요"
        }
    }

    private var title: String {
        switch phase {
        case .sending: return "보내는 중이에요"
        case .moving: return "가는 중이에요"
        case .delayed: return "평소보다 늦어지고 있어요"
        case .done: return "보냈어요"
        case .failed: return "보내지 못했어요"
        }
    }

    private var subtitle: String {
        let to = who ?? "받는 지갑"
        switch phase {
        case .sending: return "\(netName)에 거래를 올리고 있어요"
        case .moving: return "\(netName)에서 처리하고 있어요 · \(eta)"
        case .delayed: return "아직 처리 중이에요. 다시 보내지 말고 기다려 주세요"
        case .done: return own != nil ? "\(to)에 도착했어요" : "\(to)\(who == nil ? "에" : "에게") 도착했어요"
        case .failed: return tx?.via.flatMap { $0 == "전파 확인 중" || $0 == "전파 완료" ? nil : $0 } ?? "네트워크에서 처리되지 않았어요"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 위: 움직임 · 상태 · 금액
            VStack(spacing: 0) {
                SendTrack(asset: quote.asset, network: quote.network.rawValue, phase: phase,
                          recipient: recipientAvatar, reduceMotion: reduceMotion)
                    .padding(.top, 12)
                TX(title, .b, 26, align: .center, tracking: -0.6)
                    .padding(.top, 28)
                    .id(title)
                    .transition(.opacity)
                TX(subtitle, .r, 15, phase == .failed ? C.red : C.sub, lh: 21, align: .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .id(subtitle)
                    .transition(.opacity)
                VStack(spacing: 2) {
                    TX(NSDecimalNumber(decimal: qty).stringValue + " " + quote.asset.uppercased(), .b, 20, tracking: -0.4)
                    TX("약 " + wonOf(won), .r, 13, C.mute)
                }
                .padding(.top, 20)
            }
            .frame(maxWidth: .infinity)

            if uncertain && inFlight {
                HStack(alignment: .top, spacing: 10) {
                    Icon("alert-circle-outline", 18, C.amber)
                    TX("보낸 뒤 응답을 받지 못했어요. 이미 갔을 수 있으니 다시 보내지 마세요. 거래 번호로 계속 확인할게요.",
                       .r, 13, C.text, lh: 19)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(C.amberSoft))
                .padding(.top, 20)
            }

            steps.padding(.top, 24)
            details.padding(.top, 12)
        }
        .animation(.easeOut(duration: 0.25), value: phase)
        .onChange(of: phase) { _, p in
            if p == .done { haptic(.success) }
            if p == .failed { haptic(.error) }
        }
        // 화면이 떠 있는 동안 이 거래만 자주 확인 (비트코인은 블록이 느려서 길게)
        .task(id: hash) {
            let every: UInt64 = quote.network == .bitcoin ? 15 : 3
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: every * 1_000_000_000)
                guard !Task.isCancelled, tx?.inFlight == true else { break }
                await store.checkSent(txId)
            }
        }
    }

    private var recipientAvatar: AnyView {
        if own != nil { return AnyView(MineAvatar(size: 56)) }
        if let who { return AnyView(Avatar(name: who, size: 56)) }
        return AnyView(Avatar(icon: "help", color: C.surface3, size: 56))
    }

    // MARK: 단계

    private enum StepState { case done, active, wait, fail, warn }

    private var steps: some View {
        let s2: StepState = phase == .sending ? .active : .done
        let s3: StepState = {
            switch phase {
            case .sending: return .wait
            case .moving: return .active
            case .delayed: return .warn
            case .done: return .done
            case .failed: return .fail
            }
        }()
        let t3: String = s3 == .done ? "처리 완료 · 블록에 기록됐어요" : (s3 == .fail ? "처리되지 않았어요" : "처리 완료를 기다리는 중")
        return VStack(alignment: .leading, spacing: 0) {
            stepRow(.done, "본인 확인하고 서명했어요", nil, last: false)
            stepRow(s2, s2 == .active ? "네트워크에 올리는 중" : (uncertain ? "네트워크에 올렸어요 · 응답 없음" : "네트워크에 올렸어요"), nil, last: false)
            stepRow(s3, t3, s3 == .active || s3 == .warn ? elapsed : nil, last: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
    }

    /// '23초 지났어요 · 보통 몇 초면 끝나요'
    private var elapsed: AnyView {
        let since = tx?.ts ?? Date()
        return AnyView(TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = max(0, Int(ctx.date.timeIntervalSince(since)))
            let t = s < 60 ? "\(s)초" : (s < 3600 ? "\(s / 60)분 \(s % 60)초" : "\(s / 3600)시간 \(s / 60 % 60)분")
            TX("\(t) 지났어요 · \(eta)", .r, 12, phase == .delayed ? C.amber : C.mute)
        })
    }

    @ViewBuilder private func stepRow(_ state: StepState, _ title: String, _ sub: AnyView?, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    switch state {
                    case .done:
                        Circle().fill(C.text)
                        Icon("checkmark", 12, C.ink)
                    case .active:
                        Circle().strokeBorder(C.surface3, lineWidth: 1.5)
                        ProgressView().scaleEffect(0.55).tint(C.text)
                    case .warn:
                        Circle().fill(C.amberSoft)
                        ProgressView().scaleEffect(0.55).tint(C.amber)
                    case .fail:
                        Circle().fill(C.red)
                        Icon("close", 12, C.bg)
                    case .wait:
                        Circle().strokeBorder(C.faint, lineWidth: 1.5)
                    }
                }
                .frame(width: 22, height: 22)
                if !last {
                    Rectangle().fill(state == .done ? C.sub.opacity(0.5) : C.faint)
                        .frame(width: 1.5, height: 18)
                        .padding(.vertical, 3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                TX(title, state == .wait ? .r : .sb, 15, state == .wait ? C.mute : (state == .fail ? C.red : C.text))
                if let sub { sub }
            }
            .padding(.top, 1)
            Spacer(minLength: 0)
        }
    }

    // MARK: 자세한 정보

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("네트워크", netName)
            row("받는 곳", who ?? short(quote.recipient))
            if let fee = tx?.feeUpper { row("수수료 상한", fee) }
            HStack {
                TX("거래 번호", .r, 14, C.sub)
                Spacer()
                Tap(action: {
                    UIPasteboard.general.string = hash
                    haptic(.select)
                    toast("거래 번호를 복사했어요")
                }) {
                    HStack(spacing: 6) {
                        TX(short(hash), .m, 14, lines: 1)
                        Icon("copy-outline", 14, C.mute)
                    }
                }
            }
            .frame(height: 36)
            if let url = quote.network.explorer(hash) {
                Rectangle().fill(C.line).frame(height: 1).padding(.vertical, 8)
                Tap(action: { openURL(url) }) {
                    HStack {
                        TX("탐색기에서 보기", .sb, 14)
                        Spacer()
                        Icon("open-outline", 16, C.mute)
                    }
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            TX(k, .r, 14, C.sub)
            Spacer()
            TX(v, .m, 14, lines: 1)
        }
        .frame(height: 36)
    }
}

/// 내 지갑 → 받는 곳. 가는 동안 코인이 점선을 따라 건너가고, 끝나면 받는 쪽에 체크(또는 X)
private struct SendTrack: View {
    let asset: String
    let network: String
    let phase: SendProgressView.Phase
    let recipient: AnyView
    let reduceMotion: Bool

    private var moving: Bool { phase == .sending || phase == .moving || phase == .delayed }
    @State private var landed = false

    var body: some View {
        HStack(spacing: 0) {
            MineAvatar(size: 56)
            GeometryReader { g in
                let w = g.size.width, mid = g.size.height / 2
                TimelineView(.animation(paused: !moving || reduceMotion)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    // 보내는 중엔 천천히, 가는 중엔 조금 빠르게
                    let period = phase == .sending ? 2.0 : 1.4
                    let p = reduceMotion ? 0.5 : (t.truncatingRemainder(dividingBy: period)) / period
                    let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
                    let fade = reduceMotion ? 1 : min(1, min(p, 1 - p) * 6)
                    ZStack(alignment: .leading) {
                        Path { path in
                            path.move(to: CGPoint(x: 8, y: mid))
                            path.addLine(to: CGPoint(x: w - 8, y: mid))
                        }
                        .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                               dash: phase == .done ? [] : [1, 7],
                                                               dashPhase: moving && !reduceMotion ? CGFloat(-t * 24) : 0))
                        if moving {
                            CoinLogo(asset: asset, network: network, size: 28, ring: C.bg)
                                .opacity(fade)
                                .position(x: 14 + (w - 28) * eased, y: mid)
                        }
                    }
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 6)
            recipient
                .overlay(alignment: .bottomTrailing) {
                    if phase == .done || phase == .failed {
                        ZStack {
                            Circle().fill(phase == .done ? C.green : C.red)
                            Icon(phase == .done ? "checkmark" : "close", 13, C.bg)
                        }
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(C.bg, lineWidth: 2.5))
                        .scaleEffect(landed ? 1 : 0.3)
                        .offset(x: 3, y: 3)
                        .onAppear {
                            if reduceMotion { landed = true } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { landed = true }
                            }
                        }
                        .onDisappear { landed = false }
                    }
                }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(moving ? "보내는 중" : (phase == .done ? "도착" : "실패"))
    }

    private var lineColor: Color {
        switch phase {
        case .done: return C.green.opacity(0.6)
        case .failed: return C.faint
        case .delayed: return C.amber.opacity(0.7)
        default: return C.sub.opacity(0.7)
        }
    }
}
