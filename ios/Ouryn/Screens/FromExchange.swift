import SwiftUI

// src/screens/FromExchange.js
// what → exchange → register → network → test → waiting (→ 도착 | 늦어짐)
// 출금 신청 뒤에는 실제 메인넷 잔액이 늘어나는지 지켜봄 (Store.deposits)
// → 이 화면을 닫아도, 앱을 다시 열어도 이어짐

// 어떤 돈을, 어떤 네트워크로 받는지
private struct What {
    let id: String
    let net: String
    var note: String? = nil
}
private let WHAT: [What] = [
    What(id:"trx",net:"트론"),
    What(id:"mnt",net:"맨틀"),
    What(id:"avax",net:"Avalanche C-Chain"),
    What(id:"usdt0",net:"맨틀"),
    What(id: "usdc", net: ASSET_NET["usdc"] ?? ""),
    What(id: "usdt", net: ASSET_NET["usdt"] ?? ""),
    What(id: "sol", net: ASSET_NET["sol"] ?? "", note: "달러를 보낼 때 드는 수수료로 써요"),
    What(id: "eth", net: ASSET_NET["eth"] ?? ""),
    What(id: "btc", net: ASSET_NET["btc"] ?? ""),
    What(id: "ada", net: ASSET_NET["ada"] ?? "", note: "나이트를 옮길 때 드는 수수료로 써요"),
    What(id: "night", net: ASSET_NET["night"] ?? ""),
]
private let EXCHANGES = ["업비트", "빗썸", "코인원", "코빗"]
private let FLOW = ["what", "exchange", "register", "network", "test"]

struct FromExchangeView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let initialAsset: String?

    @State private var step = ""
    @State private var asset: String? = nil
    @State private var selectedNetwork: WalletNetwork? = nil
    @State private var ex: String? = nil
    @State private var copied = false
    @State private var netOk = false
    @State private var depId: String? = nil
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var w: What? { guard let asset else { return nil }; return What(id:asset,net:selectedNetwork?.rawValue ?? WHAT.first { $0.id == asset }?.net ?? "") }
    private var meta: AssetMeta? { asset.map { assetMeta($0) } }
    private var label: String { asset.map { assetFullName($0) } ?? "" }
    private var net: String { w?.net ?? "" }
    /// 이 자산의 네트워크 전용 받는 주소
    private var myAddr: String { store.st.address(net: net) ?? "" }
    private func regKey(_ e: String) -> String { "\(e)·\(net)" }
    private var already: Bool { ex.map { store.st.exRegistered[regKey($0)] ?? false } ?? false }
    private var exName: String { ex ?? "" }
    private var flow: [String] {
        FLOW.filter { !(initialAsset != nil && $0 == "what") && !(already && $0 == "register") }
    }

    var body: some View {
        Group {
            if step == "waiting" || step == "done" {
                waitingView
            } else {
                flowView
            }
        }
        .background(C.bg.ignoresSafeArea())
        .onAppear {
            if step.isEmpty {
                asset = initialAsset
                selectedNetwork = initialAsset.flatMap { a in WalletNetwork.allCases.first { $0.assets.contains(a) } }
                step = initialAsset != nil ? "exchange" : "what"
            }
        }
        .onChange(of:selectedNetwork) { _,_ in copied = false; netOk = false }
    }

    private func back() {
        if step == "what" || step == "done" { dismiss(); return }
        let prev: String?
        switch step {
        case "exchange": prev = initialAsset != nil ? nil : "what"
        case "register": prev = "exchange"
        case "network": prev = already ? "exchange" : "register"
        case "test": prev = "network"
        default: prev = nil
        }
        if let p = prev { step = p } else { dismiss() }
    }

    // 출금 신청 → 저장소에 '오는 중' 기록 (도착·지연·실패는 Store.tickDeposits)
    private func startWaiting() {
        guard let w = w, let a = asset else { return }
        now = Date()
        depId = store.startDeposit(asset: a, exchange: exName, net: w.net)
        step = "waiting"
    }

    private func copy() {
        guard !myAddr.isEmpty else { return }
        UIPasteboard.general.string = myAddr
        haptic(.success)
        copied = true
        toast("내 지갑 주소를 복사했어요")
    }

    // MARK: 도착 대기 / 완료

    private var waitingView: some View {
        let tx = store.st.tx.first { $0.id == depId }
        let status = tx?.status ?? .pending
        let phase = depId.map { store.depositPhase($0, at: now) } ?? 0
        let subs = ["출금 신청을 기다리는 중", "\(exName)가 출금을 처리하길 기다리는 중", "\(net) 네트워크에서 내 잔액을 확인하는 중", "도착했어요"]
        return Group {
            if status == .failed {
                failedView(tx)
            } else {
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 60)
                        LogoStage(done: status == .done,
                                  loadingTitle: status == .delayed ? "평소보다 늦어지고 있어요" : "\(exName)에서 오는 중이에요",
                                  loadingSub: status == .delayed ? "거래소 출금이 몰리면 늦어질 수 있어요" : subs[min(phase, 3)],
                                  doneTitle: "\(josa(label, "이/가"))\n내 지갑에 들어왔어요",
                                  doneSub: "\(tx.map { assetAmount($0.assetId, $0.quantity) } ?? "") · 다음부터는 주소 등록 없이 바로 보내면 돼요") {
                            OButton("확인") { dismiss() }
                        }
                    }
                    if status == .pending || status == .delayed {
                        VStack(spacing: 18) {
                            Tracker(phase: status == .delayed ? 2 : phase, net: net, ex: exName)
                            OButton("닫고 기다리기", kind: .ghost, md: true) { dismiss() }
                            TX("앱이 열려 있으면 15초마다 실제 잔액을 확인해요 · 닫아도 다음에 열 때 이어서 확인해요", .r, 12, C.mute, align: .center)
                                .padding(.top, -12)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .onReceive(tick) { now = $0 }
    }

    private func failedView(_ tx: Tx?) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack { Circle().fill(C.redSoft); Icon("alert-circle", 36, C.red) }
                        .frame(width: 72, height: 72)
                        .padding(.top, 40)
                    TX("\(josa(label, "이/가")) 도착하지 않았어요", .b, 26, lh: 36).padding(.top, 20)
                    TX("\(exName)에서 ‘\(net)’이 아닌 다른 네트워크로 보낸 것 같아요. 이 지갑에는 들어오지 않았어요.", .r, 15, C.sub, lh: 22)
                        .padding(.top, 10)
                    Guide(items: [
                        "\(exName) 앱 출금 내역에서 보낸 네트워크를 확인해요",
                        "다른 네트워크였다면 \(exName) 고객센터에 ‘오입금 복구’를 요청해요. 아래 거래 번호를 함께 알려주세요",
                        "복구는 거래소 사정에 따라 오래 걸리거나 안 될 수도 있어요",
                    ])
                    .padding(.top, 20)
                    if let t = tx {
                        Tap(action: {
                            UIPasteboard.general.string = t.hash
                            haptic(.success)
                            toast("거래 번호를 복사했어요")
                        }) {
                            HStack {
                                TX("거래 번호", .r, 15, C.sub)
                                Spacer()
                                TX(short(t.hash), .m, 15)
                                Icon("copy-outline", 15, C.mute)
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
                        }
                        .padding(.top, 24)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }
            OButton("확인") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    // MARK: 단계별 화면

    private var flowView: some View {
        let progress = flow.firstIndex(of: step) ?? -1
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Tap(action: back) {
                    Icon(step == "what" ? "close" : "chevron-back", 26, C.text).padding(16)
                }
                .padding(-12)
                .accessibilityLabel("뒤로")
                if progress >= 0 {
                    HStack(spacing: 6) {
                        ForEach(0..<flow.count, id: \.self) { i in
                            Capsule().fill(i <= progress ? C.text : C.surface3).frame(height: 4)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(progress + 1)/\(flow.count)단계")
                    TX("\(progress + 1)/\(flow.count)", .m, 12, C.sub)
                        .padding(.trailing, 12)
                } else {
                    Spacer()
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            switch step {
            case "what": whatStep
            case "exchange": exchangeStep
            case "register": registerStep
            case "network": networkStep
            case "test": testStep
            default: Spacer()
            }
        }
    }

    private var whatStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TX("거래소에서 산 돈을\n내 지갑으로 가져와요", .b, 26, lh: 36)
                TX("국내에선 원화로 코인을 사려면 거래소를 거쳐야 해요. 거래소에서 사고, 여기로 옮기면 그때부터 온전히 내 돈이 돼요.", .r, 15, C.sub, lh: 22)
                    .padding(.top, 10)
                Steps3()
                TX("무엇을 가져올까요?", .b, 18).padding(.top, 28).padding(.bottom, 6)
                ForEach(WHAT, id: \.id) { x in
                    let m = assetMeta(x.id)
                    let ok = store.st.address(net: x.net) != nil
                    Tap(scale: 0.98, disabled: !ok, action: { haptic(.select); asset = x.id; selectedNetwork = WalletNetwork(rawValue:x.net); step = "exchange" }) {
                        HStack(spacing: 14) {
                            AssetBadge(badge: m.badge, asset: x.id, network: x.net)
                            VStack(alignment: .leading, spacing: 0) {
                                if let s = m.sub {
                                    tt(m.name, .sb, 16) + tt("  \(s)", .r, 14, C.mute)
                                } else {
                                    tt(m.name, .sb, 16)
                                }
                                if x.id == "usdc" {
                                    TX("금액 요청에 사용", .m, 12, C.sub).padding(.top, 4)
                                }
                                TX(!ok ? "주소 검사를 통과하지 못해 잠시 막아뒀어요" : (x.note ?? "\(x.net) 네트워크 · 전용 주소로 받아요"),
                                   .r, 13, ok ? C.mute : C.red).padding(.top, 3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Icon("chevron-forward", 18, C.faint)
                        }
                        .padding(.vertical, 12)
                        .opacity(ok ? 1 : 0.5)
                    }
                }
            }
            .padding(24)
            .padding(.top, -16)
        }
    }

    private var exchangeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TX("\(josa(label, "을/를"))\n어느 거래소에서 가져올까요?", .b, 26, lh: 36)
                let nets = WalletNetwork.allCases.filter { $0.assets.contains(asset ?? "") }
                if nets.count > 1 {
                    TX("받을 네트워크", .sb, 13, C.sub).padding(.top, 18)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(nets) { n in
                                let on = selectedNetwork == n
                                Tap(action: { haptic(.select); selectedNetwork = n }) {
                                    HStack(spacing: 6) {
                                        CoinLogo(network: n.rawValue, size: 20, ring: on ? C.text : C.surface)
                                        TX(n == .avalanche ? "Avalanche" : n.rawValue, .sb, 14, on ? C.ink : C.text)
                                    }
                                    .padding(.leading, 8)
                                    .padding(.trailing, 12)
                                    .frame(height: 40)
                                    .background(Capsule().fill(on ? C.text : C.surface))
                                }
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.horizontal, -24)
                    .padding(.top, 8)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(EXCHANGES, id: \.self) { e in
                        let reg = store.st.exRegistered[regKey(e)] ?? false
                        Tap(action: {
                            haptic(.select)
                            ex = e
                            copied = false
                            netOk = false
                            step = reg ? "network" : "register"
                        }) {
                            HStack {
                                TX(e, .sb, 20)
                                Spacer()
                                if reg { TX("등록됨", .r, 12, C.green) }
                            }
                            .padding(18)
                            .frame(height: 80)
                            .background(RoundedRectangle(cornerRadius: 18).fill(C.surface))
                        }
                    }
                }
                .padding(.top, 24)
                TX("다른 거래소도 방법은 같아요. 가장 비슷한 곳을 골라 따라 해주세요.", .r, 13, C.mute, lh: 19).padding(.top, 16)
            }
            .padding(24)
            .padding(.top, -16)
        }
    }

    private var registerStep: some View {
        Page(title: "먼저 내 지갑 주소를\n거래소에 등록해요",
             sub: "\(exName)는 본인 지갑으로만 보낼 수 있도록, 받는 주소를 미리 등록하게 해요. 네트워크마다 한 번만 하면 돼요.") {
            Card(top: 18, bottom: 18, horizontal: 18) {
                HStack {
                    TX("내 \(net) 주소", .r, 13, C.mute)
                    Spacer()
                    Chip(label: "\(net) 전용")
                }
                Text(myAddr)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(C.text)
                    .lineSpacing(4)
                    .padding(.top, 8)
                OButton(copied ? "복사했어요" : "주소 복사하기", kind: .secondary, md: true, icon: copied ? "checkmark" : "copy-outline") { copy() }
                    .padding(.top, 14)
            }
            Guide(items: [
                "\(exName) 앱을 열고 출금 화면으로 가요",
                "‘개인지갑 주소 등록’ 같은 메뉴를 찾아요 (거래소마다 이름이 조금 달라요)",
                "네트워크는 ‘\(w?.net ?? "")’, 주소는 방금 복사한 주소를 붙여넣어요",
                "거래소가 본인 확인을 요청하면 안내에 따라 진행해요",
            ])
            Why(q: "왜 등록해야 하나요?", a: "‘트래블룰’이라는 규칙 때문이에요. 거래소는 돈이 누구에게 가는지 확인해야 해서, 개인 지갑으로 보낼 땐 주소를 미리 등록받아요. 내 돈을 지키기 위한 절차예요.")
        } footer: {
            OButton("등록했어요", disabled: myAddr.isEmpty) { step = "network" }
        }
    }

    private var networkStep: some View {
        let net = w?.net ?? ""
        let coinName = meta?.name ?? ""
        let picked = josa(net, "을/를")
        return Page(title: "네트워크는 꼭\n\(picked) 골라주세요",
                    sub: "출금할 때 거래소가 네트워크를 물어봐요. 여기서 틀리면 돈이 사라질 수 있어서, 이 단계가 제일 중요해요.") {
            VStack(alignment: .leading, spacing: 14) {
                Label {
                    TX("\(net) · 이 네트워크로 보내주세요", .sb, 16)
                } icon: {
                    Icon("checkmark-circle", 22, C.green)
                }
                Label {
                    TX("다른 네트워크로 보내면 돌려받기 어려워요", .r, 14, C.sub, lh: 20)
                } icon: {
                    Icon("close-circle", 22, C.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
            Notice(icon: "information-circle", color: C.sub, bg: C.surface,
                   title: "처음에는 소액으로 확인해요",
                   text: "거래소의 최소 출금액과 수수료를 확인하고, 가능한 소액부터 보내보세요. 도착을 확인한 뒤 나머지를 보내면 돼요.")
                .padding(.top, 16)
            Tap(scale: 0.99, action: { haptic(.select); netOk.toggle() }) {
                HStack(spacing: 10) {
                    Icon(netOk ? "checkbox" : "square-outline", 22, netOk ? C.text : C.mute)
                    TX("\(exName) 출금 화면에서 ‘\(net)’\(String(picked.dropFirst(net.count))) 골랐어요", .m, 15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
            }
            .padding(.top, 20)
            Why(q: "네트워크가 뭐예요?", a: "같은 \(coinName)\(hasBatchim(coinName) ? "이라도" : "라도") 오가는 길이 여러 개예요. 이번에 선택한 받는 네트워크는 ‘\(net)’이에요. 출금 네트워크와 받는 주소가 일치해야 해요.")
        } footer: {
            OButton("\(josa(net, "으로/로")) 보낼게요", disabled: !netOk) { step = "test" }
        }
    }

    private var testStep: some View {
        Page(title: "처음엔 조금만\n보내보세요",
             sub: "거래소의 최소 출금액과 수수료를 확인하고 소액부터 보내보세요. 잘 들어오면 나머지를 보내면 돼요.") {
            Card(top: 6, bottom: 6) {
                Row(k: "받는 곳", v: "내 \(net) 주소 \(short(myAddr))")
                Row(k: "네트워크", v: net, strong: true)
                Row(k: "처음 보낼 금액", v: "최소 출금액·수수료 확인 후 소액")
                Row(k: "수수료", v: "\(exName) 출금 수수료 (거래소마다 달라요)", last: true)
            }
            HStack(alignment: .top, spacing: 10) {
                Icon("notifications", 18, C.sub)
                TX("출금 신청 뒤 이 화면을 닫아도 괜찮아요. 실제 잔액이 늘어나면 도착으로 표시해요. 보통 몇 분에서 몇십 분 걸려요.", .r, 13, C.sub, lh: 19)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
        } footer: {
            OButton("출금 신청했어요") { startWaiting() }
        }
    }
}

// MARK: - 조각들

private struct Page<Content: View, Footer: View>: View {
    let title: String
    let sub: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TX(title, .b, 26, lh: 36)
                    TX(sub, .r, 15, C.sub, lh: 22).padding(.top, 10).padding(.bottom, 24)
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            footer()
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }
}

private struct Steps3: View {
    var body: some View {
        let items = [("cart", "거래소에서 사기"), ("arrow-forward", "내 지갑으로 출금"), ("wallet", "도착하면 내 돈")]
        HStack(spacing: 0) {
            ForEach(items, id: \.1) { icon, text in
                VStack(spacing: 8) {
                    ZStack { Circle().fill(C.surface2); Icon(icon, 19, C.text) }.frame(width: 40, height: 40)
                    TX(text, .m, 12, C.sub, align: .center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
        .padding(.top, 22)
    }
}

struct Guide: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().strokeBorder(C.surface3, lineWidth: 1)
                        TX("\(i + 1)", .sb, 12, C.sub)
                    }
                    .frame(width: 24, height: 24)
                    TX(t, .r, 15, lh: 22).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct Why: View {
    let q: String
    let a: String
    @State private var open = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { open.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Icon("help-circle", 18, C.mute)
                    TX(q, .m, 15).frame(maxWidth: .infinity, alignment: .leading)
                    Icon(open ? "chevron-up" : "chevron-down", 16, C.mute)
                }
                if open {
                    TX(a, .r, 14, C.sub, lh: 21).padding(.top, 10)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 24)
    }
}

private struct NetCard: View {
    let ok: Bool
    let label: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Icon(ok ? "checkmark-circle" : "close-circle", 24, ok ? C.green : C.red)
            VStack(alignment: .leading, spacing: 0) {
                TX(label, .sb, 16, ok ? C.text : C.sub)
                TX(sub, .r, 13, ok ? C.green : C.red).padding(.top, 3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(ok ? C.surface2 : C.surface))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(ok ? C.green : Color.clear, lineWidth: 1.5))
    }
}

private struct Row: View {
    let k: String
    let v: String
    var strong = false
    var last = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            TX(k, .r, 15, C.sub)
            Spacer(minLength: 0)
            TX(v, strong ? .b : .m, 15, strong ? C.green : C.text, align: .trailing)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(C.line).frame(height: 1) } }
    }
}

struct Tracker: View {
    let phase: Int
    let net: String
    let ex: String

    var body: some View {
        let steps = ["\(ex)에서 출금", "\(net) 네트워크 확인", "내 지갑 도착"]
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<steps.count, id: \.self) { i in
                let on = phase > i
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Rectangle().fill(i == 0 ? Color.clear : (phase >= i ? C.text : C.surface3)).frame(height: 2)
                        Circle().fill(on ? C.text : C.surface3).frame(width: 12, height: 12)
                        Rectangle().fill(i == steps.count - 1 ? Color.clear : (phase > i ? C.text : C.surface3)).frame(height: 2)
                    }
                    TX(steps[i], .r, 12, on ? C.text : C.mute, align: .center).padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

