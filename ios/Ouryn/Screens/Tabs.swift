import SwiftUI

// src/screens/History.js, CardScreen.js, More.js

// MARK: - 내역

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var f = "all"

    private let filters: [(String, String)] = [("all", "전체"), ("in", "받은 돈"), ("out", "보낸 돈"), ("interest", "이자")]

    private func match(_ t: Tx) -> Bool {
        switch f {
        case "in": return t.type == .receive
        case "out": return t.type == .send
        case "interest": return t.type == .interest
        case "check": return t.status != .done
        default: return true
        }
    }

    var body: some View {
        let st = store.st
        let cal = Calendar.current
        let month = cal.component(.month, from: Date())
        let inMonth = st.tx.filter { cal.component(.month, from: $0.ts) == month && $0.status == .done }
        let inSum = inMonth.filter { $0.type == .receive || $0.type == .interest }.reduce(0) { $0 + $1.amt }
        let outSum = inMonth.filter { $0.type == .send }.reduce(0) { $0 + $1.amt }
        var sections: [(String, [Tx])] = []
        for t in st.tx.filter(match) {
            let k = dayLabel(t.ts)
            if let i = sections.firstIndex(where: { $0.0 == k }) { sections[i].1.append(t) } else { sections.append((k, [t])) }
        }

        return ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                TX("내역", .b, 26).padding(.top, 28)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        TX("\(month)월에 들어온 돈", .r, 13, C.mute)
                        TX(st.hide ? "••••" : "+" + wonOf(inSum), .b, 19, C.green).padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(C.line).frame(width: 1).padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 0) {
                        TX("\(month)월에 나간 돈", .r, 13, C.mute)
                        TX(st.hide ? "••••" : "-" + wonOf(outSum), .b, 19).padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
                .padding(.top, 18)
                let needCheck = st.tx.filter { $0.status != .done }.count
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if needCheck > 0 {
                            Pill(label: "확인 필요 \(needCheck)", active: f == "check") { f = "check" }
                        }
                        ForEach(filters, id: \.0) { k, label in
                            Pill(label: label, active: f == k) { f = k }
                        }
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 4)

                if sections.isEmpty {
                    Empty(title: "해당하는 내역이 없어요")
                }
                ForEach(sections, id: \.0) { title, data in
                    TX(title, .m, 13, C.mute).padding(.top, 22).padding(.bottom, 2)
                    ForEach(data) { t in
                        TxRow(t: t) { router.push(.txDetail(t.id)) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(C.bg.ignoresSafeArea())
    }
}

// MARK: - 카드

struct CardView: View {
    @EnvironmentObject var store: Store
    @State private var open = false
    @State private var agree = false
    @State private var tilt = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let st = store.st
        let applied = st.card.status == "applied"
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TX("카드", .b, 26).padding(.top, 28)

                ZStack {
                    CardFace(width: 300, name: applied ? "발급 준비 중" : "내 이름")
                    if !reduceMotion { Sheen(every: 6, width: 90, opacity: 0.07) }
                }
                .frame(width: 300, height: 300 * 0.63)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .rotation3DEffect(.degrees(6), axis: (x: 1, y: 0, z: 0), perspective: 0.375)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : (tilt ? 8 : -8)), axis: (x: 0, y: 1, z: 0), perspective: 0.375)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)

                TX(applied ? "신청해주셔서 고마워요" : "내 달러로\n바로 결제하세요", .b, 24, lh: 34)
                TX(applied ? "사전 신청 \(grouped(Double(st.card.queue ?? 0)))번째예요. 발급이 시작되면 가장 먼저 알려드릴게요." : "지갑에 있는 달러가 결제할 때 원화로 바뀌어 나가요. 따로 충전할 필요 없어요.",
                   .r, 15, C.sub, lh: 22)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 20) {
                    Benefit(icon: "flash", title: "충전 없이 바로 결제", sub: "지갑에 있는 달러로 체크카드처럼")
                    Benefit(icon: "airplane", title: "해외에서도 달러 그대로", sub: "해외 결제 수수료는 출시 때 알려드려요")
                    Benefit(icon: "gift", title: "결제 리워드 준비 중", sub: "돌려받는 비율과 조건은 출시 때 확정돼요")
                    Benefit(icon: "lock-closed", title: "잠금은 앱에서 바로", sub: "잃어버려도 한 번 눌러 멈추기")
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 24).fill(C.surface))
                .padding(.top, 24)

                TX("아직 출시 전이에요. 혜택·수수료·연회비는 출시 전에 확정해서 안내해요.", .r, 13, C.mute, lh: 19)
                    .padding(.top, 12)
                    .padding(.horizontal, 4)

                if applied {
                    Tap(action: { store.cancelCard(); toast("사전 신청을 취소했어요", "close-circle") }) {
                        TX("사전 신청 취소하기", .r, 14, C.mute).underline(color: C.mute).padding(8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                } else {
                    OButton("사전 신청하기") { agree = false; open = true }
                        .padding(.top, 24)
                }
            }
            .padding(20)
            .padding(.bottom, 12)
        }
        .background(C.bg.ignoresSafeArea())
        .onAppear {
            if !reduceMotion { withAnimation(Ease.standard(3).repeatForever(autoreverses: true)) { tilt = true } }
        }
        .oSheet($open, title: "카드 사전 신청", sub: "지금 신청하면 발급이 시작될 때 가장 먼저 알려드려요. 신청해도 비용은 없어요.") {
            Tap(scale: 0.99, action: { haptic(.select); agree.toggle() }) {
                HStack(spacing: 10) {
                    Icon(agree ? "checkmark-circle" : "ellipse-outline", 24, agree ? C.blue : C.faint)
                    TX("출시 알림과 안내 받기에 동의해요", .m, 15)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            OButton("신청하기", disabled: !agree) {
                store.applyCard()
                open = false
                haptic(.success)
                toast("사전 신청이 완료됐어요")
            }
            .padding(.top, 12)
        }
    }
}

private struct Benefit: View {
    let icon: String
    let title: String
    let sub: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(C.surface2)
                Icon(icon, 20, C.text)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 0) {
                TX(title, .sb, 16)
                TX(sub, .r, 13, C.mute).padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 전체

struct MoreView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var resetOpen = false
    @State private var gateOpen = false
    @State private var deleteTarget: String? = nil   // "main" = 이 폰의 지갑 전체, 그 밖 = 그 지갑 id
    @State private var payOn = false
    @State private var payHelp = false
    @State private var bio = Bio.info()

    private func flip(_ fn: @escaping (inout AppState, Bool) -> Void) -> (Bool) -> Void {
        { v in haptic(.select); store.update { fn(&$0, v) } }
    }

    private func bind(_ get: @escaping (AppState) -> Bool, _ set: @escaping (inout AppState, Bool) -> Void) -> Binding<Bool> {
        Binding(get: { get(store.st) }, set: { v in store.update { set(&$0, v) } })
    }

    var body: some View {
        let st = store.st
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TX("전체", .b, 26).padding(.top, 28).padding(.bottom, 18)

                // 지금 통장 + 통장 · 지갑 관리
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Group {
                            if st.currentWallet?.isMain ?? true {
                                ZStack { Circle().fill(C.surface2); Logo(size: 52 * LOGO_IN_CIRCLE) }.frame(width: 52, height: 52)
                            } else {
                                WalletMark(wallet: st.currentWallet, size: 52)
                            }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            TX("지금 통장", .r, 12, C.mute)
                            (tt(st.accountName, .b, 18) + tt(" · \(st.currentWallet?.name ?? "Ouryn 지갑")", .m, 13, C.mute))
                                .lineLimit(1)
                                .padding(.top, 1)
                            Tap(action: {
                                UIPasteboard.general.string = st.myAddr
                                haptic(.success)
                                toast("지갑 주소를 복사했어요")
                            }) {
                                HStack(spacing: 4) {
                                    AddrText(addr: st.myAddr, size: 14, base: C.mute)
                                    Icon("copy-outline", 13, C.mute)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Tap(action: { router.present(.receive) }) {
                            ZStack { Circle().fill(C.surface2); Icon("qr-code", 18, C.text) }.frame(width: 40, height: 40)
                        }
                    }
                    .padding(20)
                    Tap(scale: 0.99, action: { router.accountSheet = true }) {
                        HStack {
                            TX("통장 · 지갑 관리", .sb, 15)
                            Spacer()
                            TX("통장 \(max(1, st.realAccounts.count))개 · 지갑 \(max(1, st.walletList.count))개", .m, 13, C.mute)
                            Icon("chevron-forward", 16, C.faint)
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 52)
                        .overlay(alignment: .top) { Rectangle().fill(C.line).frame(height: 1) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 24).fill(C.surface))

                if !st.backedUp {
                    BackupBanner { router.push(.recovery) }
                        .padding(.top, 12)
                }

                Group1 {
                    Item(icon: "card", label: "카드", sub: "출시 준비 중 · 사전 신청", value: st.card.status == "applied" ? "신청함" : nil) { router.push(.card) }
                    Item(icon: "repeat", label: "자동 보내기", value: st.schedules.isEmpty ? nil : "\(st.schedules.count)건") { router.push(.schedules) }
                    Item(icon: "notifications", label: "알림", value: st.unread > 0 ? "새 알림 \(st.unread)" : nil, valueColor: C.blueText, last: true) { router.push(.notifications) }
                }

                Label1("빠르게 결제")
                Group1 {
                    Toggle1(icon: "qr-code", label: "결제 모드", isOn: Binding(get: { payOn }, set: { v in
                        if v {
                            guard PayMode.allowed else {
                                toast("설정 → Ouryn → 실시간 현황을 켜주세요", "alert-circle")
                                return
                            }
                            payOn = PayMode.start()
                            if payOn { toast("8시간 동안 다이나믹 아일랜드에 떠 있어요", "qr-code") }
                        } else {
                            PayMode.stop()
                            payOn = false
                        }
                    }), last: true)
                    TX(payOn ? "다이나믹 아일랜드의 로고를 누르면 바로 QR을 찍어요. \(PayMode.endsAt.map { timeLabel($0) } ?? "")에 자동으로 꺼져요."
                              : "켜면 최대 8시간 동안 다이나믹 아일랜드·잠금 화면에 로고가 떠 있고, 누르면 바로 QR을 찍어요.",
                       .r, 13, C.mute, lh: 18)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
                    Item(icon: "flash", label: "항상 한 번에 QR 열기", sub: "제어 센터 · 잠금 화면 · 동작 버튼", last: true) { payHelp = true }
                }

                Label1("지갑 보관 · 지갑마다 12단어 하나")
                Group1 {
                    ForEach(st.walletList.isEmpty ? [WalletBox(id: "main", name: "Ouryn 지갑", backedUp: st.backedUp)] : st.walletList) { w in
                        WalletKeepRow(wallet: w, backedUp: st.walletBackedUp(w.id)) {
                            router.push(w.id == st.currentWallet?.id || st.walletList.isEmpty ? .recovery : .walletPhrase(w.id))
                        }
                    }
                    TX("통장은 따로 적지 않아도 돼요 · iCloud 암호화 백업은 준비 중이에요", .r, 13, C.mute, lh: 18)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Label1("보안")
                Group1 {
                    Item(icon: "keypad", label: "간편 비밀번호 바꾸기") { router.push(.changePin) }
                    Toggle1(icon: "lock-closed", label: "앱 열 때 잠그기", isOn: bind({ $0.lockEnabled }, { $0.lockEnabled = $1 }))
                    if bio.ok {
                        Toggle1(icon: bio.icon, label: "\(bio.label)으로 열기", isOn: Binding(get: { store.st.bio }, set: { v in
                            if v {
                                Bio.auth("설정 확인") { ok in if ok { haptic(.select); store.update { $0.bio = true } } }
                            } else {
                                haptic(.select)
                                store.update { $0.bio = false }
                            }
                        }), noHaptic: true)
                    }
                    Toggle1(icon: "shield-checkmark", label: "보낼 때 비밀번호 확인", isOn: bind({ $0.pinOnSend }, { $0.pinOnSend = $1 }), last: true)
                }

                Label1("화면")
                Group1 {
                    HStack(spacing: 12) {
                        IconBox(name: "cash")
                        TX("금액 보여주기", .m, 16).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 0) {
                            ForEach([("krw", "원화"), ("usd", "달러")], id: \.0) { k, l in
                                Tap(action: { haptic(.select); store.update { $0.unit = k } }) {
                                    TX(l, .sb, 13, st.unit == k ? C.text : C.mute)
                                        .padding(.horizontal, 12)
                                        .frame(height: 30)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(st.unit == k ? C.surface3 : Color.clear))
                                }
                            }
                        }
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 10).fill(C.surface2))
                    }
                    .padding(16)
                    .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
                    Item(icon: "grid", label: "홈 목록", value: st.homeMode == "list" ? "하나씩 보기" : "묶어서 보기") { router.push(.homeEdit) }
                    Toggle1(icon: "eye-off", label: "금액 가리기", isOn: bind({ $0.hide }, { $0.hide = $1 }), last: true)
                }

                Label1("알림 설정")
                Group1 {
                    Toggle1(icon: "arrow-down-circle", label: "돈이 들어오면 알림", isOn: bind({ $0.notify["receive"] ?? false }, { $0.notify["receive"] = $1 }))
                    Toggle1(icon: "leaf", label: "매일 이자 알림", isOn: bind({ $0.notify["interest"] ?? false }, { $0.notify["interest"] = $1 }))
                    Toggle1(icon: "trending-up", label: "코인이 하루 3% 넘게 움직이면 알림", isOn: bind({ $0.notify["price"] ?? true }, { $0.notify["price"] = $1 }), last: true)
                }

                Label1("기타")
                Group1 {
                    Item(icon: "chatbubbles", label: "고객센터") { toast("상담 연결은 실제 앱에서 제공돼요", "chatbubbles-outline") }
                    Item(icon: "document-text", label: "약관 및 정책") { toast("약관은 출시 전에 준비돼요", "document-text-outline") }
                    Item(icon: "globe", label: "연결된 네트워크", value: st.inTest ? "테스트넷 (테스트 통장)" : "메인넷", onPress: nil)
                    Item(icon: "shield-checkmark", label: "주소 계산 자체 검사",
                         value: WalletKeys.allPassed ? "통과" : "일부 실패",
                         valueColor: WalletKeys.allPassed ? C.green : C.red, onPress: nil)
                    Item(icon: "information-circle", label: "앱 정보", value: "0.3 개발판", last: true, onPress: nil)
                }

                Tap(action: { resetOpen = true }) {
                    TX(st.inTest ? "테스트 통장 지우기" : "이 지갑 지우기", .r, 14, C.mute).underline(color: C.mute).padding(8)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
            }
            .padding(20)
            .padding(.bottom, 20)
        }
        .background(C.bg.ignoresSafeArea())
        .onAppear { payOn = PayMode.isOn }
        .oSheet($payHelp, title: "‘Ouryn 결제’ 버튼 추가하기",
                sub: "결제 모드를 켜지 않아도, 버튼 하나로 언제든 바로 QR을 찍을 수 있어요.") {
            VStack(alignment: .leading, spacing: 14) {
                HelpRow(n: 1, title: "제어 센터", text: "화면 오른쪽 위에서 쓸어내림 → 왼쪽 위 ＋ → 컨트롤 추가 → ‘Ouryn 결제’")
                HelpRow(n: 2, title: "잠금 화면", text: "잠금 화면 길게 누르기 → 사용자화 → 잠금 화면 → 아래 손전등·카메라 자리를 눌러 ‘Ouryn 결제’로 바꾸기")
                HelpRow(n: 3, title: "동작 버튼 (아이폰 15 Pro 이상)", text: "설정 → 동작 버튼 → 제어 → ‘Ouryn 결제’")
            }
            .padding(.bottom, 12)
            OButton("확인") { payHelp = false }
        }
        .oSheet($resetOpen, title: deleteTitle, sub: deleteSub) {
            switch deleteKind {
            case .mainWithOthers:
                OButton("확인") { resetOpen = false }
            case .test:
                HStack(spacing: 8) {
                    OButton("취소", kind: .secondary) { resetOpen = false }
                    OButton("지우기", kind: .danger) {
                        resetOpen = false
                        after(0.25) { store.removeTestAccount(store.st.activeId); toast("테스트 통장을 지웠어요") }
                    }
                }
            case .extra(let w):
                deleteChoices(walletId: w.id, backedUp: st.walletBackedUp(w.id), phrase: .walletPhrase(w.id))
            case .onlyWallet:
                deleteChoices(walletId: st.currentWallet?.id ?? "main", backedUp: st.backedUp, phrase: .recovery, target: "main")
            }
        }
        // 지우기 전 간편 비밀번호 (앱이 열린 폰을 잠깐 빌린 사람도 지울 수 없게)
        .fullScreenCover(isPresented: $gateOpen) {
            PinGate(title: "간편 비밀번호를 입력해주세요", sub: "지갑을 지우려면 본인 확인이 필요해요") { ok in
                gateOpen = false
                let target = deleteTarget
                deleteTarget = nil
                if ok, let target { after(0.35) { runDelete(target) } }
            }
            .environmentObject(store)
        }
    }

    /// 12단어를 안 적었고 잔액이 0이라고 확인되지 않았으면 지우기 대신 '12단어 적기'만
    @ViewBuilder
    private func deleteChoices(walletId: String, backedUp: Bool, phrase: Route, target: String? = nil) -> some View {
        let empty = confirmedEmpty(walletId)
        if !backedUp && !empty {
            Notice(icon: "alert-circle", color: C.red, bg: C.redSoft, title: "12단어를 먼저 적어주세요",
                   text: "잔액이 있거나, 잔액을 다 확인하지 못했어요. 12단어 없이 지우면 이 지갑의 돈은 누구도 다시 꺼낼 수 없어요.")
                .padding(.bottom, 12)
            HStack(spacing: 8) {
                OButton("취소", kind: .secondary) { resetOpen = false }
                OButton("12단어 적기") {
                    resetOpen = false
                    after(0.25) { router.push(phrase) }
                }
            }
        } else {
            if !backedUp {
                Notice(icon: "alert-circle", color: C.red, bg: C.redSoft, title: "아직 12단어를 안 적었어요",
                       text: "지금은 잔액이 0이에요. 하지만 12단어가 없으면 이 지갑 주소는 다시 열 수 없어요. 앞으로 이 주소로 돈이 들어와도 꺼낼 수 없어요.")
                    .padding(.bottom, 12)
            }
            HStack(spacing: 8) {
                OButton("취소", kind: .secondary) { resetOpen = false }
                OButton("지우기", kind: .danger) {
                    resetOpen = false
                    deleteTarget = target ?? walletId
                    after(0.3) { gateOpen = true }
                }
            }
        }
    }

    /// 그 지갑의 모든 진짜 통장이 마지막 조회에서 오류 없이 잔액 0
    private func confirmedEmpty(_ walletId: String) -> Bool {
        let st = store.st
        let accs = st.accountsIn(walletId).filter { !$0.isTest }
        guard !accs.isEmpty else { return false }
        return accs.allSatisfy { a in
            let v = st.view(of: a)
            return v.lastSync != nil && v.syncFailed.isEmpty && (v.networkErrors ?? [:]).isEmpty && st.held(a).isEmpty
        }
    }

    private func runDelete(_ target: String) {
        if target == "main" {
            if !store.wipe() { toast("이 폰에서 지우지 못했어요. 폰 잠금을 푼 상태로 다시 해주세요", "alert-circle") }
            return
        }
        let name = store.st.walletList.first { $0.id == target }?.name ?? "지갑"
        if store.deleteWallet(target) { toast("\(josa(name, "을/를")) 지웠어요") }
        else { toast("이 폰에서 지우지 못했어요. 폰 잠금을 푼 상태로 다시 해주세요", "alert-circle") }
    }

    // MARK: 이 지갑 지우기

    private enum DeleteKind { case test, extra(WalletBox), onlyWallet, mainWithOthers }

    /// 지금 통장이 속한 지갑만 지움. 지갑이 하나뿐이면 처음 상태로
    private var deleteKind: DeleteKind {
        let st = store.st
        if st.inTest { return .test }
        if let w = st.currentWallet, !w.isMain { return .extra(w) }
        return st.walletList.count > 1 ? .mainWithOthers : .onlyWallet
    }

    private var deleteTitle: String {
        switch deleteKind {
        case .test: return "테스트 통장을 지울까요?"
        case .extra(let w): return "\(josa("‘" + w.name + "’", "을/를")) 이 폰에서 지울까요?"
        case .onlyWallet: return "이 지갑을 지울까요?"
        case .mainWithOthers: return "Ouryn 지갑은 마지막에 지울 수 있어요"
        }
    }

    private var deleteSub: String {
        let st = store.st
        switch deleteKind {
        case .test:
            return "테스트넷 잔액·내역만 지워져요. 진짜 통장과 12단어는 그대로고, 언제든 다시 만들 수 있어요."
        case .extra(let w):
            return "이 지갑의 12단어와 통장 \(st.accountsIn(w.id).count)개가 이 폰에서 지워지고 기본 통장으로 바뀌어요. 블록체인의 돈은 그대로지만, 12단어가 없으면 다시 꺼낼 수 없어요."
        case .onlyWallet:
            return "지갑 열쇠(복구 문구)와 설정이 이 폰에서 지워지고 처음 화면으로 돌아가요. 블록체인에 있는 돈은 그대로지만, 복구 문구가 없으면 누구도 다시 꺼낼 수 없어요."
        case .mainWithOthers:
            return "처음 만든 지갑이라 앱 잠금·설정이 여기에 묶여 있어요. 다른 지갑의 통장으로 바꾼 뒤 그 지갑부터 지워주세요."
        }
    }

}

private struct HelpRow: View {
    let n: Int
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack { Circle().strokeBorder(C.surface3, lineWidth: 1); TX("\(n)", .sb, 12, C.sub) }
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                TX(title, .sb, 15)
                TX(text, .r, 13, C.sub, lh: 19).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 지갑 보관 한 줄 (W5)
private struct WalletKeepRow: View {
    let wallet: WalletBox
    let backedUp: Bool
    let onPress: () -> Void

    var body: some View {
        Tap(scale: 0.99, action: onPress) {
            HStack(spacing: 12) {
                WalletMark(wallet: wallet, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        TX(wallet.name, .sb, 16, lines: 1)
                        StateChip(text: backedUp ? "적어둠" : "안 적음", ok: backedUp)
                    }
                    TX(wallet.isMain ? (backedUp ? "복구 문구 보기" : "복구 문구 적기")
                                     : (wallet.imported ? "가져온 지갑 · 12단어가 따로예요" : "새로 만든 지갑 · 12단어가 따로예요"),
                       .r, 13, C.mute, lines: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if backedUp {
                    Icon("chevron-forward", 18, C.faint)
                } else {
                    TX("지금 적기", .b, 13, C.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(C.text))
                        .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
        }
    }
}

private struct Label1: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        TX(text, .m, 13, C.mute).padding(.top, 24).padding(.bottom, 8).padding(.leading, 6)
    }
}

private struct Group1<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .background(C.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.top, 12)
    }
}

private struct IconBox: View {
    let name: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(C.surface2)
            Icon(name, 18, C.sub)
        }
        .frame(width: 36, height: 36)
    }
}

private struct Item: View {
    let icon: String
    let label: String
    var sub: String? = nil
    var value: String? = nil
    var valueColor: Color? = nil
    var last = false
    var onPress: (() -> Void)?

    var body: some View {
        Tap(scale: 0.99, disabled: onPress == nil, action: { onPress?() }) {
            HStack(spacing: 12) {
                IconBox(name: icon)
                VStack(alignment: .leading, spacing: 0) {
                    TX(label, .m, 16)
                    if let s = sub { TX(s, .r, 13, C.mute).padding(.top, 2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let v = value { TX(v, .m, 14, valueColor ?? C.mute) }
                if onPress != nil { Icon("chevron-forward", 18, C.faint) }
            }
            .padding(16)
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(C.line).frame(height: 1) } }
        }
    }
}

private struct Segment1: View {
    let icon: String
    let label: String
    let items: [(String, String)]
    let value: String
    let onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconBox(name: icon)
            TX(label, .m, 16).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(items, id: \.0) { k, l in
                    Tap(action: { haptic(.select); onPick(k) }) {
                        TX(l, .sb, 13, value == k ? C.text : C.mute)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(value == k ? C.surface3 : Color.clear))
                    }
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10).fill(C.surface2))
        }
        .padding(16)
        .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
    }
}

private struct Toggle1: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    var last = false
    var noHaptic = false

    var body: some View {
        HStack(spacing: 12) {
            IconBox(name: icon)
            TX(label, .m, 16).frame(maxWidth: .infinity, alignment: .leading)
            OSwitch(isOn: Binding(get: { isOn }, set: { v in
                if !noHaptic { haptic(.select) }
                isOn = v
            }))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(C.line).frame(height: 1) } }
    }
}
