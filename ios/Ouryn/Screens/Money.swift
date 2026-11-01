import SwiftUI

// src/screens/Dollar.js, Savings.js, SavingsMove.js, Coin.js, Coins.js, HomeEdit.js

// MARK: - 달러

struct DollarView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router

    private func toggle(_ k: String) {
        let on = !(store.st.notify[k] ?? false)
        store.update { $0.notify[k] = on }
        toast(on ? "나오면 바로 알려드릴게요" : "알림을 껐어요", on ? "notifications" : "notifications-off")
    }

    var body: some View {
        let st = store.st
        let total = st.walletTotal
        let txs = st.tx.filter { $0.type != .interest && $0.isDollar } // 코인 내역은 코인 화면에
        OScreen {
            VStack(spacing: 0) {
                MetalBadge(label: "$", size: 56)
                TX(st.hide ? "••••••" : wonOf(total), .b, 34, tracking: -1).padding(.top, 16)
                TX(st.hide ? "" : dollar(total), .r, 15, C.sub).padding(.top, 6)
                HStack(spacing: 4) {
                    Icon("swap-horizontal", 13, C.mute)
                    TX("1달러 = \(groupedEn(RATE))원 · 네트워크별 합산", .r, 13, C.mute)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(C.surface))
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 24)

            HStack(spacing: 8) {
                OButton("보내기") { router.sendTo(nil) }
                OButton("받기", kind: .secondary) { router.present(.receive) }
            }
            .padding(.bottom, 12)
            OButton("이자 모으기로 옮기기 · 준비 중", kind: .secondary, icon: "leaf", disabled: !LIVE_SEND) { router.push(.savingsMove("in")) }
                .padding(.bottom, 16)

            Card {
                SectionTitle(title: "내 달러 구성")
                TX("네트워크별 USDC와 USDT 잔액을 합산해 보여줘요. 보낼 때는 사용할 네트워크와 코인을 선택해요.", .r, 13, C.mute, lh: 19)
                    .padding(.bottom, 6)
                ListItem(left: AnyView(Avatar(name: "서", size: 40)), title: "서클 달러", sub: "미국 서클사가 발행", right: st.hide ? "••••" : dollar(st.wallet.circle))
                ListItem(left: AnyView(Avatar(name: "테", size: 40)), title: "테더 달러", sub: "테더사가 발행", right: st.hide ? "••••" : dollar(st.wallet.tether))
            }

            Card {
                SectionTitle(title:"네트워크별 달러")
                ForEach(WalletNetwork.allCases) { net in
                    ForEach(net.assets.filter { $0 == "usdc" || $0 == "usdt" },id:\.self) { asset in
                        ListItem(left:AnyView(Avatar(name:asset == "usdt" ? "테" : "서",size:40)),title:"\(net.rawValue) · \(asset.uppercased())",sub:st.networkErrors?[net.rawValue] ?? "마지막 확인 잔액",right:st.balance(asset,net:net.rawValue).map { dollar($0) } ?? "확인 중")
                    }
                }
            }

            Card {
                SectionTitle(title: "곧 담을 수 있어요")
                SoonRow(symbol: "₩", title: "원화", sub: "국내 원화 코인 법이 생기면 바로", on: st.notify["krw"] ?? false) { toggle("krw") }
                SoonRow(symbol: "¥", title: "엔화", sub: "일본 엔화 코인 지원 준비 중", on: st.notify["jpy"] ?? false) { toggle("jpy") }
            }

            Card {
                SectionTitle(title: "내역")
                if txs.isEmpty {
                    Empty(title: "아직 내역이 없어요")
                } else {
                    ForEach(txs) { t in TxRow(t: t) { router.push(.txDetail(t.id)) } }
                }
            }
        }
    }
}

// MARK: - 이자 모으기

private func sinceNine() -> Double {
    let now = Date()
    let cal = Calendar.current
    var nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
    if now < nine { nine = nine.addingTimeInterval(-86400) }
    return now.timeIntervalSince(nine) / 86400
}

struct SavingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router

    var body: some View {
        let st = store.st
        let daily = st.dailyInterest
        let history = st.tx.filter { $0.type == .interest || $0.type == .save || $0.type == .unsave }
        OScreen {
            VStack(alignment: .leading, spacing: 0) {
                TX("이자 모으기에 있는 돈", .m, 15, C.sub)
                TX(st.hide ? "••••••" : wonOf(st.savings.principal), .b, 34, tracking: -1).padding(.top, 8)
                TX(dollar(st.savings.principal), .r, 14, C.mute).padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 20)

            if !LIVE_SEND {
                Notice(icon: "construct-outline", color: C.sub, bg: C.surface, title: "이자 모으기는 준비 중이에요",
                       text: "어느 대출 시장에 맡길지, 이자율을 어떻게 보여줄지 정한 다음 실제로 연결할게요. 지금 보이는 숫자는 모두 0이에요.")
                    .padding(.bottom, 12)
            }
            Card(bg: Color(hex: "#0F1F1A"), border: Color(hex: "rgba(0,200,150,0.18)")) {
                HStack(spacing: 6) {
                    Circle().fill(C.green).frame(width: 8, height: 8)
                    TX(st.savings.principal > 0 ? "지금도 이자가 쌓이는 중" : "넣은 돈이 없어요", .m, 14, C.green)
                }
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    TX("+\(String(format: "%.4f", daily * sinceNine() * RATE))원", .b, 30, C.text, tracking: -0.5)
                        .monospacedDigit()
                }
                .padding(.top, 10)
                TX("내일 아침 9시에 약 \(wonOf(daily))이 들어와요", .r, 13, C.sub).padding(.top, 6)
            }

            Card {
                InfoRow(label: "연 이자율", value: "\(jsNum(st.savings.apy))%", valueColor: C.green)
                InfoRow(label: "지금까지 받은 이자", value: "+" + wonOf(st.savings.earned))
                InfoRow(label: "하루 이자", value: "약 " + wonOf(daily))
                InfoRow(label: "이대로 한 달이면", value: "약 " + wonOf(daily * 30), last: true)
            }

            Card {
                SectionTitle(title: "기록")
                if history.isEmpty {
                    Empty(title: "아직 기록이 없어요")
                } else {
                    ForEach(history) { t in TxRow(t: t) { router.push(.txDetail(t.id)) } }
                }
            }

            Card {
                SectionTitle(title: "궁금한 점")
                Faq(q: "이자는 어디서 생기나요?", a: "맡긴 달러를 검증된 대출 시장에 빌려주고, 빌린 사람이 내는 이자를 나눠 받아요. 이자율은 시장 상황에 따라 매일 조금씩 바뀔 수 있어요.")
                Faq(q: "언제든 뺄 수 있나요?", a: "보통은 빼기를 누르면 바로 쓸 수 있는 돈으로 돌아와요. 다만 빌려준 돈이 한꺼번에 많이 빠져나가는 때에는 잠시 기다려야 할 수 있어요. 중도 해지 불이익은 없어요.")
                Faq(q: "원금이 줄어들 수도 있나요?", a: "은행 예금이 아니라서 예금자 보호를 받지 않아요. 드물지만 빌려준 곳에 문제가 생기면 손실이 날 수 있어요. 꼭 알고 넣어주세요.", last: true)
            }
        } footer: {
            GeometryReader { g in
                HStack(spacing: 8) {
                    OButton("빼기", kind: .secondary, disabled: !LIVE_SEND || st.savings.principal <= 0) { router.push(.savingsMove("out")) }
                        .frame(width: (g.size.width - 8) / 3)
                    OButton(LIVE_SEND ? "넣기" : "넣기 · 준비 중", disabled: !LIVE_SEND) { router.push(.savingsMove("in")) }
                        .frame(width: (g.size.width - 8) * 2 / 3)
                }
            }
            .frame(height: 56)
        }
    }
}

struct Faq: View {
    let q: String
    let a: String
    var last = false
    @State private var open = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { open.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    TX(q, .m, 15)
                    Spacer()
                    Icon(open ? "chevron-up" : "chevron-down", 18, C.mute)
                }
                if open {
                    TX(a, .r, 14, C.sub, lh: 21).padding(.top, 10)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(C.line).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 넣기 / 빼기

struct SavingsMoveView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let mode: String

    @State private var amt: Double = 0
    @State private var over = false
    @State private var step = "amount"

    private var inbound: Bool { mode == "in" }

    var body: some View {
        let st = store.st
        let apy = st.savings.apy / 100 / 365
        Group {
            if step != "amount" {
                // 진행·완료 화면에선 헤더 숨김 (로고 위치 고정)
                LogoStage(done: step == "done",
                          loadingTitle: inbound ? "이자 모으기에 넣는 중이에요" : "꺼내는 중이에요",
                          doneTitle: "\(wonOf(amt))을\n\(inbound ? "넣었어요" : "꺼냈어요")",
                          doneSub: inbound ? "이제 하루에 약 \(wonOf(st.savings.principal * apy))씩 이자를 받아요" : "바로 쓸 수 있는 돈으로 옮겼어요") {
                    OButton("확인") { router.pop() }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    TX(inbound ? "얼마를 넣을까요?" : "얼마를 꺼낼까요?", .b, 24)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    AmountEntry(max: inbound ? st.walletTotal : st.savings.principal,
                                maxLabel: inbound ? "넣을 수 있는 돈" : "꺼낼 수 있는 돈",
                                quick: inbound) { v, o in amt = v; over = o }
                    VStack(spacing: 0) {
                        if inbound && amt > 0 && !over {
                            HStack(spacing: 6) {
                                TX("하루 이자", .r, 14, C.sub)
                                TX(wonOf(st.savings.principal * apy), .sb, 14, C.sub)
                                Icon("arrow-forward", 14, C.green)
                                TX(wonOf((st.savings.principal + amt) * apy), .sb, 14, C.green)
                            }
                            .padding(.bottom, 12)
                        }
                        OButton(inbound ? "넣기" : "꺼내기", disabled: !(amt > 0) || over) { start() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(C.bg.ignoresSafeArea())
        .toolbar(step == "amount" ? .visible : .hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(step != "amount")
    }

    private func start() {
        step = "working"
        after(1.2) {
            if inbound { store.saveIn(amt) } else { store.saveOut(amt) }
            step = "done"
        }
    }
}

// MARK: - 코인 상세

struct CoinView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let id: String

    var body: some View {
        let st = store.st
        let a = assetLine(st, id)
        let up = (a.change ?? 0) >= 0
        OScreen {
            VStack(spacing: 0) {
                AssetBadge(badge: a.badge, size: 56, asset: id)
                TX(a.name, .m, 15, C.sub).padding(.top, 14)
                TX(st.hide ? "••••••" : won(a.krw), .b, 34, tracking: -1).padding(.top, 6)
                TX(a.sub, .r, 15, C.sub).padding(.top, 6)
                TX("오늘 \(up ? "+" : "")\(won(st.coinTodayKrw(id))) (\(pct(a.change ?? 0)))", .sb, 14, up ? C.up : C.down)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(up ? Color(hex: "rgba(255,100,100,0.12)") : Color(hex: "rgba(91,140,255,0.12)")))
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 24)

            // 아직 블록에 안 들어간 비트코인 입금 — 잔액에는 블록에 들어간 뒤에 더함
            if id == "btc" && st.btcIncoming > 0 {
                Notice(icon: "time-outline", color: C.amber, bg: C.amberSoft, title: "확인 중인 입금 \(qtyText(st.btcIncoming))",
                       text: "아직 블록에 들어가지 않아서 잔액에는 더하지 않았어요. 보통 10분쯤 뒤 블록에 들어가면 잔액에 더해지고 내역에 남아요.")
                    .padding(.bottom, 12)
            }

            // 최근 5건 (트론 입금 기록은 과거 시각으로 늦게 들어올 수 있어서 시각순으로 다시 정렬)
            Card {
                SectionTitle(title: "내역")
                let txs = st.tx.filter { $0.assetId == id }.sorted { $0.ts > $1.ts }
                if txs.isEmpty {
                    Empty(title: "아직 내역이 없어요", sub: "받거나 보내면 여기에 쌓여요")
                } else {
                    ForEach(txs.prefix(5)) { t in TxRow(t: t) { router.push(.txDetail(t.id)) } }
                    if txs.count > 5 {
                        Tap(action: { router.push(.coinHistory(id)) }) {
                            HStack(spacing: 4) {
                                TX("전체 보기 · \(txs.count)건", .sb, 15)
                                Icon("chevron-forward", 15, C.faint)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .overlay(alignment: .top) { Rectangle().fill(C.line).frame(height: 1) }
                        }
                    }
                }
            }

            ChartToggle {
                CoinChart(id: id, price: st.prices[id] ?? 0, change: st.change[id] ?? 0)
            }

            Card(top: 4, bottom: 4) {
                InfoRow(label: "1개 가격", value: won(st.prices[id] ?? 0))
                InfoRow(label: "오늘 등락", value: pct(a.change ?? 0), valueColor: up ? C.up : C.down)
                InfoRow(label: "네트워크", value: ASSET_NET[id] ?? "")
                InfoRow(label: "이자", value: "없음", last: true)
            }

            HStack(alignment: .top, spacing: 10) {
                Icon("pulse", 20, C.mute)
                TX("달러와 달리 가격이 매일 오르내려요. 넣은 돈보다 줄어들 수 있어요. 시세는 CoinGecko 원화 기준이라 몇 분 늦을 수 있어요.", .r, 13, C.sub, lh: 19)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
            .padding(.bottom, 12)
        } footer: {
            // 늘 보내기 · 받기. 아직 없으면 보내기만 잠기고, 받기로 바로 받을 수 있음
            let has = st.balance(id) > 0
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    OButton("보내기", kind: has ? .primary : .secondary, disabled: !has) {
                        router.send(PayRequest(to: "", network: ASSET_NET[id], asset: id))
                    }
                    OButton("받기", kind: has ? .secondary : .primary) { router.receive(id) }
                }
                Tap(action: { router.present(.fromExchange(asset: id)) }) {
                    TX(has ? "거래소에서 가져오기" : "거래소에서 산 \(assetMeta(id).name) 가져오기", .m, 13, C.sub).padding(.vertical, 6)
                }
            }
        }
    }
}

// "그래프 보기"를 누르면 펼쳐지고, 다시 누르면 접힘
struct ChartToggle<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var open = false
    @State private var mounted = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                haptic(.select)
                let next = !open
                if next { mounted = true }
                withAnimation(Ease.outCubic(0.32)) { open = next } completion: {
                    if !next { mounted = false }
                }
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Icon("analytics", 18, C.sub)
                        TX(open ? "그래프 접기" : "그래프 보기", .sb, 16)
                    }
                    Spacer()
                    Icon("chevron-down", 18, C.mute)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(spacing: 0) {
                if mounted { content() }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: open ? 340 : 0, alignment: .top)
            .opacity(open ? 1 : 0)
            .clipped()
        }
        .background(C.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.bottom, 12)
    }
}

// MARK: - 코인 목록 (묶어서 보기에서 '코인'을 눌렀을 때)

struct CoinsView: View {
    @EnvironmentObject var router: Router

    var body: some View {
        OScreen {
            Card(top: 8, bottom: 8) {
                ForEach(COIN_IDS, id: \.self) { id in
                    AssetRow(id: id) { router.push(.coin(id)) }
                }
            }
            OButton("거래소에서 가져오기", kind: .secondary, icon: "download-outline") { router.present(.fromExchange(asset: nil)) }
                .padding(.bottom, 16)
            TX("코인은 가격이 오르내려요. 오르면 빨강, 내리면 파랑이에요.\n솔라나·에이다는 각 네트워크에서 수수료로 쓰여요.", .r, 13, C.mute, lh: 19, align: .center)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 홈 편집

struct HomeEditView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let st = store.st
        let list = st.homeMode == "list"
        VStack(alignment: .leading, spacing: 0) {
            // 어느 통장의 홈인지 — 보기 방식·순서는 통장마다 따로
            HStack(spacing: 6) {
                if st.inTest { Icon("flask", 13, C.down) } else { WalletMark(wallet: st.currentWallet, size: 18) }
                TX(st.accountTitle + "의 홈 · 통장마다 따로 정해요", .m, 13, C.sub, lines: 1)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)

            // 고르기 — 늘 위에 고정
            HStack(spacing: 0) {
                ForEach([("group", "묶어서 보기"), ("list", "하나씩 보기")], id: \.0) { k, l in
                    Tap(action: { haptic(.select); withAnimation(.easeOut(duration: 0.2)) { store.update { $0.homeMode = k } } }) {
                        TX(l, .sb, 15, st.homeMode == k ? C.text : C.mute)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10).fill(st.homeMode == k ? C.surface3 : Color.clear))
                    }
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 14).fill(C.surface2))
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if list {
                // 하나씩 보기: 설명은 고정, 목록만 스크롤 · 순서 바꾸기는 iOS 기본 끌기(끝까지 끌면 자동으로 스크롤)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        TX("이렇게 보여요", .b, 18)
                        Spacer()
                        Tap(action: {
                            store.update { $0.assetOrder = ASSET_IDS }
                            toast("기본 순서로 되돌렸어요", "refresh")
                        }) { TX("기본 순서로", .r, 14, C.mute) }
                    }
                    .padding(.bottom, 6)
                    TX("위 5개만 먼저 보이고, 나머지는 홈에서 펼치면 보여요. 오른쪽 ≡ 를 끌어서 순서를 바꿔요.", .r, 13, C.mute, lh: 19)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

                List {
                    ForEach(st.homeAssets, id: \.self) { id in
                        AssetRow(id: id)
                            .padding(.horizontal, 14)
                            .frame(height: 64)
                            .background(RoundedRectangle(cornerRadius: 18).fill(C.surface))
                            .listRowInsets(EdgeInsets(top: 3, leading: 20, bottom: 3, trailing: 8))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove { from, to in
                        haptic(.select)
                        // 보이는 목록에서 옮기고, 숨긴 자산(준비 중인 이자 모으기)은 뒤에 그대로 붙여 둠
                        var shown = st.homeAssets
                        shown.move(fromOffsets: from, toOffset: to)
                        store.update { s in s.assetOrder = shown + s.assetOrder.filter { !shown.contains($0) } }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .environment(\.editMode, .constant(.active))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        TX("이렇게 보여요", .b, 18).padding(.bottom, 6)
                        TX("서클·테더 달러는 ‘달러’ 하나로, 코인 \(COIN_IDS.count)개는 ‘코인’ 하나로 묶여요.", .r, 13, C.mute, lh: 19)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 10)
                        VStack(spacing: 0) {
                            AssetRow(id: "usdc", rightNode: AnyView(EmptyView()))
                            AssetRow(id: "savings", rightNode: AnyView(EmptyView()))
                            AssetRow(id: "eth", rightNode: AnyView(EmptyView()))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
                        .opacity(0.8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(C.bg.ignoresSafeArea())
    }
}

private struct ModeCard: View {
    let active: Bool
    let icon: String
    let title: String
    let sub: String
    let onPress: () -> Void

    var body: some View {
        Tap(action: onPress) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Icon(icon, 22, active ? C.text : C.mute)
                    Spacer()
                    Icon(active ? "checkmark-circle" : "ellipse-outline", 20, active ? C.text : C.faint)
                }
                VStack(alignment: .leading, spacing: 0) {
                    TX(title, .sb, 16, active ? C.text : C.sub)
                    TX(sub, .r, 12, C.mute).padding(.top, 3)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .edge(18, active ? C.surface2 : C.surface)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(active ? C.text : Color.clear, lineWidth: 1.5))
        }
    }
}
