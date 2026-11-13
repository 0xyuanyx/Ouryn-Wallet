import SwiftUI

// src/screens/Home.js

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var listOpen = false   // 하나씩 보기: 6번째부터 펼쳤는지

    private func money(_ usd: Double) -> String {
        let st = store.st
        return st.hide ? "••••••" : (st.unit == "krw" ? wonOf(usd) : dollar(usd))
    }

    var body: some View {
        let st = store.st
        VStack(spacing: 0) {
            // 헤더
            HStack {
                // 지금 통장 — 누르면 통장 고르기
                Tap(action: { router.accountSheet = true }) {
                    HStack(spacing: 8) {
                        Group {
                            if st.currentWallet?.isMain ?? true {
                                ZStack {
                                    Circle().fill(C.surface)
                                    Circle().strokeBorder(C.surface3, lineWidth: 1)
                                    Logo(size: 26 * LOGO_IN_CIRCLE).opacity(store.unlocking ? 0 : 1)
                                }
                                .frame(width: 26, height: 26)
                            } else {
                                WalletMark(wallet: st.currentWallet, size: 26)
                            }
                        }
                        TX(st.accountName, .b, 15, lines: 1)
                        Icon("chevron-down", 12, C.sub)
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 12)
                    .frame(height: 38)
                    .background(Capsule().fill(C.surface))
                }
                .accessibilityLabel("통장 바꾸기: \(st.accountName)")
                Spacer()
                HStack(spacing: 18) {
                    Tap(action: { router.push(.notifications) }) {
                        Icon("notifications", 24, C.sub)
                            .overlay(alignment: .topTrailing) {
                                if st.unread > 0 {
                                    Circle().fill(C.red).frame(width: 9, height: 9)
                                        .overlay(Circle().strokeBorder(C.bg, lineWidth: 1.5))
                                        .offset(x: 2, y: -2)
                                }
                            }
                    }
                    .accessibilityLabel("알림")
                }
            }
            .frame(height: 52)
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    if !st.isEmptyWallet {
                        HStack(spacing: 8) {
                            // 달러든 코인이든 뭐라도 있으면 보내기
                            if st.hasBalance {
                                Action(icon: "arrow-up", label: "보내기", primary: true) { router.sendTo(nil) }
                            }
                            Action(icon: "arrow-down", label: "받기", primary: !st.hasBalance) { router.present(.receive) }
                        }
                        .padding(.bottom, 12)
                    }

                    if st.inTest {
                        TestnetBanner { router.push(.faucet) }
                    } else if !st.backedUp {
                        BackupBanner { router.push(.recovery) }
                    }

                    // 진행 중인 입금 (화면을 닫았어도 여기서 이어서 확인)
                    ForEach(st.inFlight) { t in
                        InFlightBanner(t: t) { router.push(.txDetail(t.id)) }
                    }

                    if st.isEmptyWallet {
                        firstMoney
                    } else {
                        // 내 돈 — 묶어서 / 하나씩
                        Card(top: 18, bottom: 8) {
                            SectionTitle(title: st.homeMode == "list" ? "내 지갑" : "내 돈", right: "편집") { router.push(.homeEdit) }
                            if st.homeMode == "list" {
                                let shown = listOpen ? st.assetOrder : Array(st.assetOrder.prefix(5))
                                ForEach(shown, id: \.self) { id in
                                    AssetRow(id: id) { router.push(assetRoute(id)) }
                                }
                                if st.assetOrder.count > 5 {
                                    Tap(action: { withAnimation(.easeOut(duration: 0.25)) { listOpen.toggle() } }) {
                                        HStack(spacing: 4) {
                                            TX(listOpen ? "접기" : "\(st.assetOrder.count - 5)개 더 보기", .m, 14, C.sub)
                                            Icon(listOpen ? "chevron-up" : "chevron-down", 14, C.sub)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                    }
                                }
                            } else {
                                grouped
                            }
                        }
                    }

                    // 최근
                    Card {
                        SectionTitle(title: "최근 내역", right: st.tx.isEmpty ? nil : "전체") { router.tab = .history }
                        if st.tx.isEmpty {
                            Empty(title: "아직 내역이 없어요", sub: "돈이 들어오거나 나가면 여기에 보여요")
                        }
                        ForEach(Array(st.tx.prefix(3))) { t in
                            TxRow(t: t) { router.push(.txDetail(t.id)) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            // 아래로 당기면 잔액 다시 읽기 (읽는 동안 위쪽 로딩 유지)
            .refreshable {
                await store.refresh()
            }
        }
        .background(C.bg.ignoresSafeArea())
    }

    private var hero: some View {
        let st = store.st
        let total = st.grandTotal
        let d = st.todayKrw
        let base = total * RATE - d
        let p = base > 0 ? d / base * 100 : 0
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                haptic(.select)
                store.update { $0.hide.toggle() }
            } label: {
                HStack(spacing: 6) {
                    TX(st.inTest ? "테스트 통장 · 실제 가치 없음" : (st.accountList.count > 1 ? st.accountTitle : "내 돈 전체"), .m, 15, C.sub)
                    Icon(st.hide ? "eye-off" : "eye", 16, C.mute)
                }
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-8)

            Button {
                if st.hide { return }
                haptic(.select)
                store.update { $0.unit = $0.unit == "krw" ? "usd" : "krw" }
            } label: {
                Group {
                    if st.hide {
                        TX("••••••", .b, 36, tracking: -1.2)
                    } else {
                        CountUp(value: total, format: { v in st.unit == "krw" ? wonOf(v) : dollar(v) })
                            .id(st.unit)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            SyncLine()
                .padding(.top, 10)
            if total > 0 {
                (tt("오늘 \(d >= 0 ? "+" : "")\(st.hide ? "••••" : won(d)) (\(p >= 0 ? "+" : "")\(String(format: "%.2f", p))%)", .m, 14, d >= 0 ? C.up : C.down)
                    + tt(st.savings.principal > 0 ? "  이자 +\(wonOf(st.dailyInterest)) 포함" : "", .r, 14, C.mute))
                    .padding(.top, 8)
            } else {
                TX("지갑이 준비됐어요 · 아직 들어온 돈이 없어요", .r, 14, C.mute).padding(.top, 8)
            }
            // 통장이 여럿이면 전체 합계
            if st.realAccounts.count > 1 {
                Tap(action: { router.accountSheet = true }) {
                    HStack(spacing: 4) {
                        TX("통장 \(st.realAccounts.count)개 전체 \(st.hide ? "••••••" : wonOf(st.allAccountsUsd))", .m, 12, C.sub)
                        Icon("chevron-forward", 12, C.faint)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Capsule().fill(C.surface))
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 28)
    }

    @ViewBuilder private var grouped: some View {
        let st = store.st
        // 코인 3개의 가치 가중 평균 등락률
        let coinsKrw = COIN_IDS.reduce(0.0) { $0 + st.coinKrw($1) }
        let coinsChange = coinsKrw > 0 ? COIN_IDS.reduce(0.0) { $0 + (st.coinKrw($1) / coinsKrw) * (st.change[$1] ?? 0) } : 0
        let held = COIN_IDS.filter { (st.coins[$0] ?? 0) > 0 }
        let coinSub = held.isEmpty ? "아직 없어요" : (held.count == 1 ? assetMeta(held[0]).name : "\(assetMeta(held[0]).name) 외 \(held.count - 1)개")
        ListItem(left: AnyView(MetalBadge(label: "$")), title: "달러", sub: "바로 쓸 수 있는 돈",
                 right: money(st.walletTotal)) { router.push(.dollar) }
        AssetRow(id: "savings") { router.push(.savings) }
        ListItem(left: AnyView(MetalBadge(icon: "stats-chart")), title: "코인", sub: coinSub,
                 right: money(st.coinsUsd), rightSub: coinsKrw > 0 ? pct(coinsChange) : nil,
                 rightSubColor: coinsChange >= 0 ? C.up : C.down) { router.push(.coins) }
    }
}

extension HomeView {
    /// 0원 첫 화면: 거래소에서 가져오기가 자연스러운 첫 행동
    fileprivate var firstMoney: some View {
        Card(top: 22, bottom: 20) {
            MetalBadge(icon: "download-outline", size: 48)
            TX("첫 돈을 가져와 볼까요?", .b, 20).padding(.top, 16)
            TX("거래소에서 산 달러나 코인을 이 지갑으로 옮겨요. 처음이어도 단계마다 알려드려요.",
               .r, 14, C.sub, lh: 21)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            OButton("거래소에서 가져오기", icon: "arrow-forward") { router.present(.fromExchange(asset: nil)) }
                .padding(.top, 18)
            Tap(action: { router.present(.receive) }) {
                TX("친구에게 받기 · 내 QR", .m, 14, C.sub).padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
    }
}

/// 마지막으로 잔액을 읽은 때 · 실패한 네트워크 (누르면 이유)
private struct SyncLine: View {
    @EnvironmentObject var store: Store
    @State private var open = false

    private func label(_ net: String) -> String {
        guard let n = WalletNetwork(rawValue: net) else { return net }
        return Testnet.on ? Testnet.name(n) : n.rawValue
    }

    var body: some View {
        let st = store.st
        let failed = st.syncFailed
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if store.syncing {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12).tint(C.mute)
                    TX("잔액 확인 중", .r, 12, C.mute)
                } else if !failed.isEmpty {
                    Icon("cloud-offline-outline", 13, C.amber)
                    TX("\(label(failed[0]))\(failed.count > 1 ? " 외 \(failed.count - 1)곳" : "") 잔액을 못 읽었어요 · 당겨서 다시", .r, 12, C.amber, lines: 1)
                    Icon(open ? "chevron-up" : "chevron-down", 12, C.amber)
                } else if let t = st.lastSync {
                    Icon("checkmark-circle-outline", 13, C.mute)
                    TX(Date().timeIntervalSince(t) < 60 ? "방금 확인한 잔액이에요" : "\(relTime(t)) 확인한 잔액이에요", .r, 12, C.mute)
                }
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !store.syncing, !failed.isEmpty else { return }
                haptic(.select)
                withAnimation(.easeOut(duration: 0.2)) { open.toggle() }
            }
            if open && !store.syncing && !failed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(failed, id: \.self) { net in
                        TX("\(label(net)) · \(st.networkErrors?[net] ?? "잔액 확인 실패")", .r, 12, C.sub, lines: 2)
                    }
                    TX("이전에 읽은 잔액을 그대로 보여주고 있어요", .r, 12, C.mute, lines: 1)
                }
                .padding(.leading, 19)
                .transition(.opacity)
            }
        }
        .onChange(of: failed.isEmpty) { _, empty in if empty { open = false } }
    }
}

/// 복구 문구를 아직 안 적었을 때
struct BackupBanner: View {
    let onPress: () -> Void
    var body: some View {
        Tap(scale: 0.985, action: onPress) {
            HStack(spacing: 12) {
                ZStack { Circle().fill(C.amberSoft); Icon("key", 18, C.amber) }
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    TX("복구 문구를 적어주세요", .sb, 15)
                    TX("돈을 넣기 전에 복구 문구부터 적어주세요", .r, 13, C.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TX("지금 적기", .sb, 13, C.text)
                    .fixedSize()
            }
            .padding(14)
            .edge(18, C.surface)
        }
        .padding(.bottom, 12)
    }
}

/// 오는 중·늦어지는 입금 한 줄
private struct InFlightBanner: View {
    @EnvironmentObject var store: Store
    let t: Tx
    let onPress: () -> Void

    var body: some View {
        let late = t.status == .delayed
        let from = t.via ?? store.st.nameOf(t.addr,net:t.network) ?? "거래소"
        Tap(scale: 0.985, action: onPress) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(C.amberSoft)
                    Icon(late ? "time" : "arrow-down", 18, C.amber)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    TX("\(josa(assetFullName(t.assetId), "이/가")) 오는 중이에요", .sb, 15)
                    TX(late ? "평소보다 늦어지고 있어요 · \(from)" : "\(t.network) 네트워크에서 확인 중 · \(from)", .r, 13, late ? C.amber : C.mute, lines: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon("chevron-forward", 16, C.faint)
            }
            .padding(14)
            .edge(18, C.surface)
        }
        .padding(.bottom, 12)
    }
}

private struct Action: View {
    let icon: String
    let label: String
    let primary: Bool
    let onPress: () -> Void

    var body: some View {
        Tap(haptics: .light, action: onPress) {
            HStack(spacing: 6) {
                Icon(icon, 19, primary ? C.ink : C.text)
                TX(label, .sb, 16, primary ? C.ink : C.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Group {
                    if primary {
                        RoundedRectangle(cornerRadius: 16).fill(metalGradient())
                    } else {
                        Color.clear.edge(16, C.surface)
                    }
                }
            )
        }
    }
}
