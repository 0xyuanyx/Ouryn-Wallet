import SwiftUI

// TxDetail.js, Contacts.js, ContactDetail.js, ContactEdit.js, Notifications.js,
// Recovery.js, ChangePin.js, Schedules.js

func isAddr(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return WalletNetwork.allCases.contains { WalletKeys.valid(t, network:$0) }
}

// MARK: - 거래 상세

struct TxDetailView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.openURL) private var openURL
    let id: String

    @State private var more = false
    @State private var memoOpen = false
    @State private var nickOpen = false
    @State private var text = ""

    private func copy(_ v: String, _ label: String) {
        UIPasteboard.general.string = v
        haptic(.success)
        toast("\(label)를 복사했어요")
    }

    var body: some View {
        let st = store.st
        if let t = st.tx.first(where: { $0.id == id }) {
            detail(st, t)
        } else {
            C.bg.ignoresSafeArea()
        }
    }

    private func stateText(_ s: TxStatus) -> String {
        switch s {
        case .done: return "최종 확정"
        case .pending: return "네트워크 확인 중"
        case .delayed: return "네트워크 확인 중 (지연)"
        case .failed: return "실패"
        }
    }

    /// 자세한 정보 — 칸 순서 고정, 값이 없으면 회색 "—"
    @ViewBuilder
    private func detailRows(_ st: AppState, _ t: Tx, _ m: TxMeta) -> some View {
        let network = WalletNetwork(rawValue: t.network)
        InfoRow(label: "네트워크", value: t.network)
        InfoRow(label: "종류", value: m.verb)
        if t.type == .send {
            InfoRow(label: "네트워크 수수료", value: t.feeUpper.map { "상한 " + $0 } ?? "거래 탐색기에서 확인", valueColor: C.sub)
        } else {
            InfoRow(label: "네트워크 수수료", value: "—", valueColor: C.faint)
        }
        let addrLabel = t.type == .send ? "받는 주소" : "보낸 주소"
        if let a = t.addr {
            InfoRow(label: addrLabel, value: short(a), right: AnyView(Icon("copy-outline", 15, C.mute))) { copy(a, "지갑 주소") }
        } else {
            InfoRow(label: addrLabel, value: "—", valueColor: C.faint)
        }
        if !t.hash.isEmpty {
            InfoRow(label: "거래 번호", value: short(t.hash), right: AnyView(Icon("copy-outline", 15, C.mute))) { copy(t.hash, "거래 번호") }
        } else {
            InfoRow(label: "거래 번호", value: "—", valueColor: C.faint)
        }
        // 거래 번호가 없으면 특정 거래 대신 내 주소 페이지 (시간·금액으로 찾기)
        let byHash = !t.hash.isEmpty
        let url = byHash ? network?.explorer(t.hash) : network?.explorer(address: st.address(net: t.network) ?? "")
        if let url {
            InfoRow(label: "탐색기", value: byHash ? "거래 탐색기에서 확인" : "내 지갑 주소 거래 내역 보기", valueColor: C.blueText,
                    right: AnyView(Icon("open-outline", 13, C.blueText)), last: !byHash) { openURL(url) }
        } else {
            InfoRow(label: "탐색기", value: "—", valueColor: C.faint, last: !byHash)
        }
        if !byHash {
            TX(t.type == .receive ? "잔액이 늘어난 것을 보고 남긴 기록이라 거래 번호가 없어요. 시각은 앱이 확인한 때이고, 그 사이 여러 번 받았거나 같이 보낸 돈이 있으면 실제 입금과 금액이 다를 수 있어요. 정확한 내역은 탐색기에서 확인해주세요."
                                  : "거래 번호가 남아 있지 않아요", .r, 12, C.mute, lh: 17)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
        }
        InfoRow(label: "처리 상태", value: stateText(t.status), last: true)
    }

    @ViewBuilder
    private func detail(_ st: AppState, _ t: Tx) -> some View {
        let m = txMeta(st, t)
        let name = st.nameOf(t.addr,net:t.network)
        let person = t.type == .send || t.type == .receive
        let settled = t.status == .done
        let status = txStatusLabel(t)
        let deposit = store.deposit(t.id)
        let noSource = t.type == .receive && t.addr == nil && t.via == nil
        // 보낸 곳/받는 분: 사용자가 붙인 이름 > 거래소 이름(받음) > 모름
        let party = name ?? (t.type == .receive ? t.via : nil) ?? (noSource ? "보낸 곳을 몰라요" : "모르는 지갑")
        // 내 다른 통장(또는 이 통장)과 주고받은 거래 — '님'을 붙이지 않음
        let own = t.addr.flatMap { st.ownAccount(address: $0, net: t.network) }
        let ownTitle = own.flatMap { o in name == o.title ? o.title : nil }
        let headline: String = {
            if t.via != nil && t.addr == nil { return "\(t.via ?? "")에서 가져옴" }
            if let o = ownTitle, person { return t.type == .send ? "\(josa(o, "으로/로")) 보냄" : "\(o)에서 받음" }
            return m.title + (person && !noSource ? (t.type == .send ? "님에게 보냄" : "님이 보냄") : "")
        }()
        OScreen {
            VStack(spacing: 0) {
                m.avatar.view(60)
                TX(headline, .m, 16, C.sub).padding(.top, 14)
                TX(t.inFlight && t.amt == 0 ? "금액 확인 중" : (settled ? (m.sign > 0 ? "+" : (m.sign < 0 ? "-" : "")) : "") + wonOf(t.amt), .b, t.inFlight && t.amt == 0 ? 26 : 34,
                   !settled ? C.sub : (m.sign > 0 ? C.green : C.text), tracking: -1)
                    .padding(.top, 6)
                TX(person ? "\(assetFullName(t.assetId))\(t.qty != nil || t.isDollar && t.amt > 0 ? " " + assetAmount(t.assetId, t.quantity) : "")" : dollar(t.amt), .r, 14, C.mute).padding(.top, 4)
                if let s = status {
                    Chip(label: s.0, color: s.1, bg: s.2).padding(.top, 12)
                } else {
                    Chip(label: "완료", color: C.green, bg: C.greenSoft).padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 24)

            // 모르는 주소에서 온 소액: 내가 자주 보내는 주소와 비슷하게 만든 주소로 소액을 보내 두고,
            // 나중에 그 주소로 보내게 만드는 사기(주소 오염)일 수 있음
            if t.type == .receive && t.addr != nil && name == nil && t.amt < 5 {
                Notice(icon: "warning", color: C.amber, bg: C.amberSoft, title: "모르는 주소에서 온 소액이에요",
                       text: "자주 보내는 주소와 앞뒤 글자가 비슷한 주소로 소액을 보내, 나중에 그 주소로 돈을 보내게 만드는 사기가 있어요. 이 주소를 복사하거나 이 주소로 보내지 마세요.")
                    .padding(.bottom, 12)
            }

            // 진행 중 / 늦어짐 / 실패 안내
            if t.inFlight && t.type != .send {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    VStack(alignment: .leading, spacing: 16) {
                        Tracker(phase: t.status == .delayed ? 2 : store.depositPhase(t.id, at: ctx.date),
                                net: t.network, ex: deposit?.exchange ?? "거래소")
                        if t.status == .delayed {
                            TX("거래소 출금이 몰리면 늦어질 수 있어요. \(deposit?.exchange ?? "거래소") 앱 출금 내역이 ‘완료’인데 안 들어왔다면 출금한 네트워크와 주소를 확인해주세요.",
                               .r, 13, C.sub, lh: 19)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            TX("실제 잔액이 늘어나면 도착으로 바뀌어요. 앱이 열려 있으면 15초마다 확인해요.", .r, 13, C.sub, lh: 19)
                            Tap(action: { store.cancelDeposit(t.id); router.pop() }) {
                                TX("기다리기 그만", .m, 13, C.mute).underline(color: C.mute).padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
                .padding(.bottom, 12)
            } else if t.inFlight {
                Notice(icon:"time",color:C.sub,bg:C.surface,title:"네트워크 확인 중",text:"거래 해시로 전파·확정을 확인하고 있어요. 확인이 끝날 때까지 같은 송금을 다시 보내지 마세요.").padding(.bottom,12)
            } else if t.status == .failed {
                Notice(icon: "alert-circle", color: C.red, bg: C.redSoft,
                       title: t.type == .receive ? "이 지갑에 도착하지 않았어요" : "보내지 못했어요",
                       text: t.type == .receive
                           ? "다른 네트워크로 보낸 것 같아요. 보낸 거래소 고객센터에 ‘오입금 복구’를 요청하고, 아래 거래 번호를 알려주세요. 복구가 안 될 수도 있어요."
                           : "송금이 완료되지 않았어요. 처리 중 발생한 네트워크 수수료가 있을 수 있으니 거래 탐색기와 현재 잔액을 확인해주세요.")
                    .padding(.bottom, 12)
            }

            Card(top: 4, bottom: 4) {
                InfoRow(label: "일시", value: fullDate(t.ts))
                if person {
                    if let a = t.addr {
                        InfoRow(label: t.type == .send ? "받는 분" : "보낸 곳", value: party,
                                right: AnyView(Icon("chevron-forward", 16, C.faint))) {
                            if st.contacts[a] != nil { router.push(.contactDetail(a)) } else { router.push(.walletDetail(a, t.network)) }
                        }
                    } else {
                        // 주소를 모르면 더 볼 곳이 없음 → 화살표·탭 없음
                        InfoRow(label: t.type == .send ? "받는 분" : "보낸 곳", value: party)
                    }
                    InfoRow(label: "자산", value: assetFullName(t.assetId))
                    InfoRow(label: "수량", value: t.inFlight && t.qty == nil ? "도착하면 보여요" : assetAmount(t.assetId, t.quantity))
                } else {
                    InfoRow(label: "종류", value: m.verb)
                }
                InfoRow(label: "메모", value: t.memo.isEmpty ? "메모 남기기" : t.memo, valueColor: t.memo.isEmpty ? C.mute : C.text,
                        right: AnyView(Icon("pencil", 14, C.faint)), last: true) {
                    text = t.memo
                    memoOpen = true
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) { more.toggle() }
            } label: {
                HStack(spacing: 4) {
                    TX("자세한 정보", .r, 14, C.mute)
                    Icon(more ? "chevron-up" : "chevron-down", 14, C.mute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if more || t.status == .failed {
                Card(top: 4, bottom: 4) {
                    if person {
                        detailRows(st, t, m)
                    } else {
                        if let a = t.addr {
                            InfoRow(label: "지갑 주소", value: short(a), right: AnyView(Icon("copy-outline", 15, C.mute))) { copy(a, "지갑 주소") }
                        }
                        if !t.hash.isEmpty {
                            InfoRow(label: "거래 번호", value: short(t.hash), right: AnyView(Icon("copy-outline", 15, C.mute))) { copy(t.hash, "거래 번호") }
                        }
                        InfoRow(label: "처리 상태", value: stateText(t.status), last: true)
                    }
                }
            }

        } footer: {
            if person && !t.inFlight {
                HStack(spacing: 8) {
                    if name == nil && t.addr != nil {
                        OButton("이름 붙이기", kind: .secondary) { text = ""; nickOpen = true }
                    }
                    if t.type == .send && t.status == .failed {
                        OButton("다시 보내기") { router.send(PayRequest(to:t.addr ?? "",network:t.network,asset:t.assetId)) }
                    } else if t.isDollar && (t.type == .send || name != nil) {
                        // 받은 거래는 이름을 붙인(주소록·내 통장) 보낸 사람에게만 '보내기' — 주소 오염 사기로 모르는 주소에 보내지 않게
                        OButton(t.type == .send ? "한 번 더 보내기" : "보내기") { router.send(PayRequest(to:t.addr ?? "",network:t.network,asset:t.assetId)) }
                    }
                }
            }
        }
        .oSheet($memoOpen, title: "메모") {
            Field(text: $text, placeholder: "이 거래를 기억할 메모", autoFocus: true, maxLength: 20)
            OButton("저장") {
                store.setMemo(t.id, text.trimmingCharacters(in: .whitespaces))
                memoOpen = false
                toast("메모를 저장했어요")
            }
            .padding(.top, 12)
        }
        .oSheet($nickOpen, title: "이 지갑에 이름 붙이기", sub: "\(t.network) 네트워크의 이 주소에 붙어요 · 이름은 이 폰에만 저장돼요") {
            if let a = t.addr {
                AddressGroups(address: a, size: 14)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(C.surface2))
                    .padding(.bottom, 14)
            }
            Field(text: $text, placeholder: "예: 민지, 월세, 거래소", autoFocus: true, maxLength: 12)
            OButton("저장", disabled: text.trimmingCharacters(in: .whitespaces).isEmpty) {
                let n = text.trimmingCharacters(in: .whitespaces)
                if let a = t.addr { store.saveRecipient(network:t.network,address:a,name:n) }
                nickOpen = false
                toast("'\(n)'(으)로 저장했어요")
            }
            .padding(.top, 12)
        }
    }
}

// MARK: - 주소록

struct ContactsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    /// 탭으로 쓸 때: 제목·'새 주소'를 화면 안에 (툴바는 다른 탭에도 보이므로 안 씀)
    var embedded = false
    @State private var q = ""

    var body: some View {
        let query = q.trimmingCharacters(in: .whitespaces)
        let list = store.st.contacts
            .filter { query.isEmpty || $0.value.name.contains(query) }
            .sorted { $0.value.name.compare($1.value.name, locale: Locale(identifier: "ko_KR")) == .orderedAscending }
        let saved = (store.st.savedRecipients ?? []).filter { query.isEmpty || $0.name.contains(query) || $0.address.lowercased().contains(query.lowercased()) }
        let recent = query.isEmpty ? recentSends(store.st, limit: 10) : []
        OScreen(pad: 24) {
            if embedded {
                HStack {
                    TX("주소록", .b, 26)
                    Spacer()
                    Tap(action: { router.contactEdit = true }) {
                        HStack(spacing: 4) { Icon("add", 15, C.text); TX("새 주소", .sb, 14) }
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Capsule().fill(C.surface2))
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            Field(text: $q, placeholder: "이름이나 주소로 찾기")

            if !recent.isEmpty {
                TX("최근 보낸 사람", .b, 14, C.sub).padding(.top, 24)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recent) { t in
                            let a = t.addr ?? ""
                            let name = store.st.nameOf(a, net: t.network)
                            Tap(action: { router.send(PayRequest(to: a, network: t.network, asset: t.assetId)) }) {
                                VStack(spacing: 6) {
                                    Group {
                                        if let name { Avatar(name: name, size: 52) }
                                        else { CoinLogo(network: t.network, size: 52) }
                                    }
                                    .networkBadge(name != nil ? t.network : nil, size: 52)
                                    TX(name ?? short(a), name != nil ? .sb : .r, name != nil ? 13 : 11, name != nil ? C.text : C.sub, lines: 1)
                                }
                                .frame(width: 76)
                            }
                            .accessibilityLabel("\(name ?? short(a))에게 보내기")
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.horizontal, -24)
                .padding(.top, 12)
            }

            if !saved.isEmpty {
                TX("저장한 주소 · \(saved.count)", .b, 14, C.sub).padding(.top, 26)
                ForEach(saved) { recipient in
                    HStack(spacing: 10) {
                        NavigationLink {
                            SavedRecipientDetailView(recipient: recipient).environmentObject(store).environmentObject(router)
                        } label: {
                            RecipientRow(r: recipient).frame(minHeight: 64)
                        }
                        .buttonStyle(.plain)
                        Tap(action: { router.send(PayRequest(to: recipient.address, network: recipient.network)) }) {
                            TX("보내기", .sb, 13)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Capsule().fill(C.surface2))
                        }
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(C.surface).frame(height: 1) }
                }
            }

            if !list.isEmpty {
                TX("이름 붙인 사람", .b, 14, C.sub).padding(.top, 26)
                ForEach(list, id: \.key) { a, c in
                    ListItem(left: AnyView(Avatar(name: c.name)), title: c.name, sub: short(a), chevron: true) {
                        router.push(.contactDetail(a))
                    }
                }
            }

            if list.isEmpty && saved.isEmpty && recent.isEmpty {
                Empty(icon: "people-outline", title: q.isEmpty ? "아직 아무도 없어요" : "찾는 사람이 없어요", sub: "자주 보내는 지갑에 이름을 붙여두면 편해요")
                    .padding(.top, 20)
            }

            TX("이름은 이 폰에만 저장되고, 누구에게도 공유되지 않아요.", .r, 13, C.mute, lh: 19, align: .center)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        }
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.contactEdit = true } label: { Icon("person-add", 22, C.text) }
                }
            }
        }
    }
}

struct ContactDetailView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let addr: String

    @State private var rename = false
    @State private var del = false
    @State private var text = ""
    @State private var removed = false

    var body: some View {
        let st = store.st
        if let c = st.contacts[addr], !removed {
            let txs = st.tx.filter { $0.addr == addr }
            let sent = txs.filter { $0.type == .send && $0.status == .done }.reduce(0) { $0 + $1.amt }
            let got = txs.filter { $0.type == .receive && $0.status == .done }.reduce(0) { $0 + $1.amt }
            OScreen {
                VStack(spacing: 0) {
                    Avatar(name: c.name, size: 76)
                    TX(c.name, .b, 26).padding(.top, 16)
                    Tap(action: {
                        UIPasteboard.general.string = addr
                        haptic(.success)
                        toast("지갑 주소를 복사했어요")
                    }) {
                        HStack(spacing: 4) {
                            TX(short(addr), .r, 13, C.sub)
                            Icon("copy-outline", 13, C.sub)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(C.surface))
                    }
                    .padding(.top, 8)
                    HStack(spacing: 8) {
                        OButton("이름 바꾸기", kind: .secondary, md: true, icon: "pencil", expand: false) { text = c.name; rename = true }
                        OButton("삭제", kind: .secondary, md: true, icon: "trash-outline", expand: false) { del = true }
                    }
                    .padding(.top, 18)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 24)

                HStack(spacing: 8) {
                    Stat(label: "내가 보낸 돈", value: wonOf(sent))
                    Stat(label: "받은 돈", value: wonOf(got), color: C.green)
                }
                .padding(.bottom, 12)

                Card {
                    SectionTitle(title: "주고받은 내역")
                    if txs.isEmpty {
                        Empty(title: "아직 주고받은 적이 없어요")
                    } else {
                        ForEach(txs) { t in TxRow(t: t) { router.push(.txDetail(t.id)) } }
                    }
                }
            } footer: {
                OButton("\(c.name)님에게 보내기") { router.sendTo(addr) }
            }
            .oSheet($rename, title: "이름 바꾸기") {
                Field(text: $text, autoFocus: true, maxLength: 12)
                OButton("저장", disabled: text.trimmingCharacters(in: .whitespaces).isEmpty) {
                    store.setContact(addr, text.trimmingCharacters(in: .whitespaces))
                    rename = false
                    toast("이름을 바꿨어요")
                }
                .padding(.top, 12)
            }
            .oSheet($del, title: "\(c.name)님을 지울까요?", sub: "주소록에서만 지워지고, 주고받은 내역은 그대로 남아요.") {
                HStack(spacing: 8) {
                    OButton("취소", kind: .secondary) { del = false }
                    OButton("지우기", kind: .danger) {
                        del = false
                        toast("주소록에서 지웠어요", "trash-outline")
                        after(0.25) {
                            router.pop()
                            after(0.3) { store.removeContact(addr) }
                        }
                    }
                }
            }
        } else {
            OScreen { Empty(title: "삭제된 연락처예요") }
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var color: Color = C.text

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TX(label, .r, 13, C.mute)
            TX(value, .b, 17, color).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(C.surface))
    }
}

struct ContactEditView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    /// 닫기 (없으면 router.contactEdit)
    var onDone: (() -> Void)? = nil
    @State private var name = ""
    @State private var addr = ""
    /// 0x 주소의 네트워크 — 사용자가 직접 고르기 전에는 비어 있음 (QR 에 네트워크가 적혀 있으면 그걸로)
    @State private var evm: WalletNetwork? = nil
    @State private var evmAddr = ""   // 그 선택이 어느 주소에 대한 건지 (주소를 바꾸면 다시 골라야 함)
    @State private var scan = false

    private var clean: String { addr.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// 주소 모양으로 찾은 네트워크 — 0x 는 이더리움·맨틀·Avalanche 셋
    private var detected: [WalletNetwork] { WalletNetwork.detect(clean) }
    private var network: WalletNetwork? {
        if detected.count == 1 { return detected[0] }
        if detected.count > 1, evmAddr == clean, let evm, detected.contains(evm) { return evm }
        return nil
    }

    var body: some View {
        let exists = network.flatMap { n in (store.st.savedRecipients ?? []).first { $0.id == SavedRecipient(network: n.rawValue, address: clean, name: "").id } }
        NavigationStack {
            OScreen(pad: 24) {
                TX("새 주소 저장", .b, 26)
                TX("주소만 넣으면 네트워크는 알아서 찾아요", .r, 15, C.sub).padding(.top, 6)

                TX("지갑 주소", .sb, 13, C.sub).padding(.top, 28)
                AddressField(text: $addr, placeholder: "받을 지갑 주소", onScan: { scan = true }).padding(.top, 6)
                if addr.isEmpty && UIPasteboard.general.hasStrings {
                    Tap(action: { addr = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }) {
                        HStack(spacing: 8) {
                            Icon("clipboard-outline", 16, C.blueText)
                            TX("복사한 주소 붙여넣기", .r, 13, C.blue)
                            Spacer(minLength: 0)
                            TX("붙여넣기", .b, 13, C.text)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(C.blueSoft))
                    }
                    .padding(.top, 8)
                }

                if detected.count > 1 {
                    TX("0x 주소는 이더리움·맨틀·Avalanche가 모양이 같아요. 어느 네트워크인가요?", .r, 13, C.sub, lh: 19).padding(.top, 12)
                    HStack(spacing: 6) {
                        ForEach(detected) { d in
                            Tap(action: { evm = d; evmAddr = clean }) {
                                HStack(spacing: 6) {
                                    CoinLogo(network: d.rawValue, size: 16)
                                    TX(d == .avalanche ? "Avalanche" : d.rawValue, .sb, 13, d == network ? C.ink : C.text)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 36)
                                .background(Capsule().fill(d == network ? C.text : C.surface3))
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                if let n = network {
                    HStack(spacing: 12) {
                        CoinLogo(network: n.rawValue, size: 32, ring: C.surface)
                        VStack(alignment: .leading, spacing: 2) {
                            TX("\(n.rawValue) 네트워크 주소예요", .b, 15)
                            TX(n.assets.map { $0.uppercased() }.joined(separator: " · ") + "를 보낼 수 있어요", .r, 13, C.sub)
                        }
                        Spacer(minLength: 0)
                        Icon("checkmark", 20, C.green)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(C.greenSoft))
                    .padding(.top, 10)
                }
                if let n = network, let own = store.st.ownAccount(address: clean, net: n.rawValue) {
                    let test = store.st.accountList.first { $0.id == own.id }?.isTest == true
                    HStack(spacing: 12) {
                        MineAvatar(size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            TX(own.active ? "지금 보고 있는 통장의 주소예요" : "내 ‘\(own.title)’ 주소예요", .b, 15)
                            TX((test ? "테스트넷 · " : "") + "이름을 붙여 저장해도 돼요", .r, 13, C.sub)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(C.addr.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(C.addr.opacity(0.22), lineWidth: 1))
                    .padding(.top, 8)
                }
                if network == nil && detected.isEmpty && clean.count >= 20 {
                    TX("지갑 주소 형식이 아니에요", .r, 13, C.red).padding(.top, 8)
                }
                if let e = exists { TX("이미 '\(e.name)'(으)로 저장된 주소예요", .r, 13, C.amber).padding(.top, 8) }

                TX("이름", .sb, 13, C.sub).padding(.top, 24)
                Field(text: $name, placeholder: "예: 엄마, 룸메이트, 업비트", maxLength: 12).padding(.top, 6)
            } footer: {
                OButton("저장", disabled: name.trimmingCharacters(in: .whitespaces).isEmpty || network == nil || exists != nil) {
                    guard let n = network else { return }
                    let v = name.trimmingCharacters(in: .whitespaces)
                    store.saveRecipient(network: n.rawValue, address: clean, name: v)
                    toast("\(v)님을 추가했어요")
                    close()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { close() } label: { Icon("close", 24, C.text) }.accessibilityLabel("닫기")
                }
            }
            .toolbarBackground(C.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .fullScreenCover(isPresented: $scan) {
                ScanView(fromSend: true) { req in
                    scan = false; addr = req.to
                    if let raw = req.network, let n = WalletNetwork(rawValue: raw), n.isEVM { evm = n; evmAddr = req.to.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                    .environmentObject(store).environmentObject(router)
            }
        }
        .presentationBackground(C.bg)
    }

    private func close() {
        if let onDone { onDone() } else { router.contactEdit = false }
    }
}

// MARK: - 알림

struct NotificationsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router

    private func iconColor(_ i: String) -> Color {
        switch i {
        case "leaf": return C.green
        case "trending-up": return C.up
        case "trending-down": return C.down
        case "arrow-down": return C.blueText
        case "alert-circle": return C.red
        case "time": return C.amber
        default: return C.sub
        }
    }

    var body: some View {
        let list = store.st.visibleNotifications
        OScreen {
            if list.isEmpty {
                Empty(icon: "notifications-off-outline", title: "알림이 없어요")
            } else {
                ForEach(list) { n in
                    Button { open(n) } label: {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack { Circle().fill(C.surface); Icon(n.icon, 20, iconColor(n.icon)) }
                                .frame(width: 42, height: 42)
                            VStack(alignment: .leading, spacing: 0) {
                                if let acc = accountOf(n) { AccountTag(account: acc, wallet: store.st.walletList.first { $0.id == acc.walletId }).padding(.bottom, 5) }
                                TX(n.title, n.read ? .m : .sb, 15, n.read ? C.sub : C.text, lh: 21)
                                TX("\(n.body) · \(relTime(n.ts))", .r, 13, C.mute).padding(.top, 3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if !n.read {
                                Circle().fill(C.blue).frame(width: 8, height: 8).padding(.top, 8)
                            }
                            if n.action != nil {
                                Icon("chevron-forward", 16, C.faint).padding(.top, 12)
                            }
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(n.action == nil)
                }
            }
        }
        .onAppear { after(1.5) { store.readAll() } }
    }

    /// 통장이 둘 이상이거나 테스트 통장일 때만 어느 통장인지 표시 (하나뿐이면 군더더기)
    private func accountOf(_ n: Noti) -> Account? {
        let st = store.st
        guard let id = n.accountId, let acc = st.accountList.first(where: { $0.id == id }) else { return nil }
        return st.realAccounts.count > 1 || acc.isTest ? acc : nil
    }

    /// 알림을 누르면 그 일이 생긴 곳으로 — 다른 통장의 알림이면 그 통장으로 바꾼 뒤
    private func open(_ n: Noti) {
        guard let action = n.action else { return }
        if action == "recovery" { router.push(.recovery); return }
        // "asset:<자산>|<통장>" · "tx:<내역 id>|<통장>"
        let kind = action.prefix { $0 != ":" }
        let parts = action.dropFirst(kind.count + 1).split(separator: "|", maxSplits: 1).map(String.init)
        guard let target = parts.first else { return }
        if parts.count > 1, parts[1] != store.st.activeId, let acc = store.st.accountList.first(where: { $0.id == parts[1] }) {
            // 다른 통장의 알림 → 그 통장으로 바꾸고 알려줌
            store.switchAccount(acc.id)
            toast("통장을 바꿨어요 · \(acc.name)", "swap-horizontal")
        }
        if kind == "asset" { router.push(assetRoute(target)) }
        if kind == "tx", store.st.tx.contains(where: { $0.id == target }) { router.push(.txDetail(target)) }
    }
}

// MARK: - 복구 문구 (Keychain 의 실제 12단어)

struct RecoveryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    /// nil = 지금 통장의 지갑
    var walletId: String? = nil
    @State private var step = "warn"
    /// 비밀번호 + Face ID 를 통과한 뒤에만 채움 (화면을 떠나거나 앱을 벗어나면 비움)
    @State private var words: [String] = []
    @State private var pinError: String? = nil
    @Environment(\.scenePhase) private var scenePhase

    private var wallet: WalletBox? {
        let id = walletId ?? store.st.currentWallet?.id ?? "main"
        return store.st.walletList.first { $0.id == id }
    }
    private var keyId: String { wallet?.id ?? walletId ?? "main" }
    private var needsQuiz: Bool { !store.st.walletBackedUp(wallet?.id ?? "main") }
    /// 지갑이 여럿이거나 Ouryn 지갑이 아니면 어느 지갑의 12단어인지 같이 보여줌
    private var labeled: Bool { store.st.walletList.count > 1 || (wallet.map { !$0.isMain } ?? false) }

    var body: some View {
        content
            // 앱을 벗어나거나(앱 전환·알림 센터·전화 포함) 앱이 잠기면 꺼낸 12단어를 버리고, 다시 볼 때 처음부터 본인 확인
            .onChange(of: scenePhase) { _, p in if p != .active { forget() } }
            .onChange(of: store.locked) { _, l in if l { forget() } }
    }

    private func forget() {
        guard step == "show" || step == "quiz" else { return }
        words = []
        pinError = nil
        step = "pin"
    }

    @ViewBuilder private var content: some View {
        switch step {
        case "pin":
            PinPad(title: "간편 비밀번호를 입력해주세요", sub: "복구 문구를 보려면 본인 확인이 필요해요",
                   error: pinError, length: PinVault.length) { p in
                let r = store.checkPin(p)
                guard case .ok = r else { return r }
                // 10번 넘게 틀린 뒤에 맞힌 비밀번호로는 12단어를 보여주지 않음 (Face ID 등록이 바뀌었거나 생체인증이 없는 지갑일 때)
                if PinVault.hardLocked && (Biometry.changed() || !WalletKeys.isBiometric(keyId)) {
                    return .message("비밀번호를 여러 번 틀려서 지금은 볼 수 없어요. 잠금 화면의 '비밀번호를 잊었어요'로 다시 정해주세요")
                }
                haptic(.success)
                reveal()
                return .ok
            }
            .background(C.bg.ignoresSafeArea())
            .onDisappear { if step != "show" && step != "quiz" { words = [] } }
        case "show":
            OScreen {
                if labeled, let w = wallet {
                    banner(w).padding(.bottom, 20)
                    TX("이 지갑의 12단어예요", .b, 24)
                    (tt("종이에 적을 때 맨 위에 ", .r, 15, C.sub) + tt("'\(w.name)'", .b, 15)
                     + tt(hasBatchim(w.name) ? "이라고" : "라고", .r, 15, C.sub)
                     + tt(" 같이 적어두세요. 지갑마다 문구가 달라서 섞이면 복구가 안 돼요.", .r, 15, C.sub))
                        .lineSpacing(lineGap(15, 22))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                } else {
                    TX("종이에 순서대로 적어주세요", .b, 24)
                    TX("이 12단어가 있으면 새 폰에서도, 표준 경로를 쓰는 지갑 앱(Phantom·MetaMask 등)에서도 지갑을 되찾을 수 있어요. 앱마다 주소를 만드는 방식이 달라 일부 네트워크는 직접 찾아야 할 수 있어요.", .r, 15, C.sub, lh: 22)
                        .padding(.top, 8)
                }
                MnemonicGrid(words: words).padding(.top, 24)
                TX("복사하기는 일부러 막아뒀어요. 복사한 내용은 다른 앱이 몰래 읽을 수 있거든요.", .r, 13, C.mute, lh: 19, align: .center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            } footer: {
                OButton("다 적었어요") {
                    // 아직 안 적은 지갑(새로 만든 지갑 포함)은 처음처럼 두 단어 확인
                    if needsQuiz { step = "quiz"; return }
                    if let w = wallet { store.markBackedUp(wallet: w.id) } else { store.markBackedUp() }
                    router.pop()
                }
            }
        case "quiz":
            PhraseQuiz(words: words, onBack: { step = "show" }) {
                haptic(.success)
                if let w = wallet { store.markBackedUp(wallet: w.id) } else { store.markBackedUp() }
                toast(labeled ? "\(wallet?.name ?? "지갑") 12단어를 확인했어요" : "복구 문구를 확인했어요")
                router.pop()
            }
            .background(C.bg.ignoresSafeArea())
        default:
            OScreen {
                if labeled, let w = wallet { banner(w).padding(.bottom, 20) }
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(C.redSoft)
                    Icon("warning", 28, C.red)
                }
                .frame(width: 56, height: 56)
                TX("복구 문구는\n지갑 그 자체예요", .b, 24, lh: 34).padding(.top, 20)
                TX("지금은 이 12단어가 유일한 백업이에요. 폰을 잃어버리거나 앱을 지우면 이 단어로만 되찾을 수 있어요.", .r, 15, C.sub, lh: 22)
                    .padding(.top, 10)
                VStack(alignment: .leading, spacing: 18) {
                    Warn(text: "누군가 이 단어를 알면 내 돈을 전부 가져갈 수 있어요")
                    Warn(text: "저희는 절대 복구 문구를 묻지 않아요. 묻는 사람은 사기예요")
                    Warn(text: "화면 캡처나 사진으로 남기지 말고 종이에 적어주세요")
                }
                .padding(.top, 28)
            } footer: {
                OButton("확인했어요") { step = "pin" }
            }
        }
    }

    /// Face ID 로 Keychain 의 12단어를 꺼냄 (생체인증 없는 지갑은 비밀번호만으로 열림)
    private func reveal() {
        Task { @MainActor in
            switch await WalletKeys.unlock(wallet: keyId, reason: "복구 문구 보기") {
            case .words(let m):
                words = m.split(separator: " ").map(String.init)
                pinError = nil
                step = "show"
            case .cancelled:
                pinError = nil
            case .failed:
                pinError = "Face ID로 열지 못했어요. 다시 시도해주세요"
            }
        }
    }

    /// 어느 지갑의 12단어인지 (W6)
    private func banner(_ w: WalletBox) -> some View {
        HStack(spacing: 10) {
            WalletMark(wallet: w, size: 30)
            TX(w.name, .b, 15, lines: 1).frame(maxWidth: .infinity, alignment: .leading)
            TX(w.isMain ? "처음 만든 지갑" : "Ouryn 지갑과 다름", .sb, 12, w.isMain ? C.mute : C.amber)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 16).fill(w.isMain ? C.surface : C.amber.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(w.isMain ? C.line : C.amber.opacity(0.35), lineWidth: 1))
    }
}

/// 잘 적었는지 두 단어 확인 (온보딩과 같은 방식 · 지갑 추가·나중에 적기에서 씀)
struct PhraseQuiz: View {
    let words: [String]
    var onBack: (() -> Void)? = nil
    let onPass: () -> Void
    @State private var quiz: [Int] = []
    @State private var options: [[String]] = []
    @State private var index = 0
    @State private var picked: String? = nil
    @State private var bad = false

    var body: some View {
        let ready = quiz.count == 2 && options.count == 2 && options.allSatisfy { $0.count == 6 } && quiz.indices.contains(index)
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TX("잘 적었는지\n확인해볼게요", .b, 26, lh: 36)
                    TX("적어둔 종이를 보고 골라주세요.", .r, 15, C.sub).padding(.top, 10)
                    if ready {
                        TX("확인 \(index + 1)/2", .m, 14, C.sub).padding(.top, 28)
                        TX("\(quiz[index] + 1)번째 단어", .sb, 18).padding(.top, 10)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(options[index], id: \.self) { word in
                                Tap(action: { picked = word; bad = false }) {
                                    TX(word, .sb, 16)
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(C.surface2))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(picked == word ? C.text : C.line, lineWidth: 1)
                                        }
                                }
                                .accessibilityAddTraits(picked == word ? [.isSelected] : [])
                            }
                        }
                        .padding(.top, 16)
                    } else {
                        TX("확인 문제를 준비하지 못했어요. 뒤로 가서 다시 시도해주세요.", .r, 15, C.red)
                            .padding(.top, 28)
                    }
                    if bad {
                        TX("맞지 않는 단어예요. 적어둔 종이를 다시 확인해주세요.", .r, 13, C.red).padding(.top, 16)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            OButton(index == 0 ? "확인하고 다음으로" : "확인", disabled: !ready || picked == nil) {
                guard ready else { return }
                let position = quiz[index]
                guard words.indices.contains(position), picked == words[position] else {
                    haptic(.error); bad = true; return
                }
                if index == 0 { index = 1; picked = nil; bad = false } else { onPass() }
            }
            .padding(.top, 16)
            if let onBack {
                Tap(action: onBack) { TX("12단어 다시 보기", .m, 14, C.sub).padding(10) }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .onAppear(perform: start)
    }

    private func start() {
        quiz = [12, 24].contains(words.count) ? Array(words.indices.shuffled().prefix(2)).sorted() : []
        options = quiz.map { QuizOptions.get($0, words) }
        index = 0; picked = nil; bad = false
    }
}

/// 알림 위 작은 표시 — 어느 지갑의 어느 통장인지 (지갑이 여럿이면 지갑 이름도)
struct AccountTag: View {
    @EnvironmentObject var store: Store
    let account: Account
    let wallet: WalletBox?

    var body: some View {
        let manyWallets = store.st.walletList.count > 1
        HStack(spacing: 5) {
            if account.isTest {
                Icon("flask", 11, C.down)
            } else {
                WalletMark(wallet: wallet, size: 14)
            }
            TX(manyWallets ? "\(wallet?.name ?? "") · \(account.name)" : account.name, .sb, 11, account.isTest ? C.down : C.sub, lines: 1)
            if account.id == store.st.activeId {
                TX("지금 통장", .r, 11, C.mute)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(account.isTest ? C.down.opacity(0.14) : C.surface2))
        .fixedSize()
    }
}

/// 12단어 격자 — 꾹 누르고 있는 동안만 보임
struct MnemonicGrid: View {
    let words: [String]
    var compact = false // 첫 백업 화면: 한 화면에 다 들어오게 조금 촘촘히
    @State private var reveal = false
    @State private var captured = UIScreen.main.isCaptured   // 화면 녹화·미러링 중
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: compact ? 6 : 8), GridItem(.flexible(), spacing: compact ? 6 : 8)], spacing: compact ? 6 : 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    HStack(spacing: 10) {
                        TX("\(i + 1)", .m, 13, C.mute).frame(width: 20, alignment: .leading)
                        if reveal {
                            TX(w, .sb, 16)
                        } else {
                            RoundedRectangle(cornerRadius: 4).fill(C.surface3)
                                .frame(width: 64, height: 14)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: compact ? 42 : 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(C.surface2))
                }
            }
            .padding(compact ? 12 : 16)
            .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !reveal && !captured && phase == .active { haptic(.light); reveal = true } }
                    .onEnded { _ in reveal = false }
            )
            .onChange(of: phase) { _, p in if p != .active { reveal = false } }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                captured = UIScreen.main.isCaptured
                if captured { reveal = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
                toast("12단어를 캡처했다면 사진을 지우고 종이에만 남겨주세요", "alert-circle")
            }
            .accessibilityLabel(reveal ? words.joined(separator: " ") : "복구 문구, 꾹 누르면 보여요")
            // VoiceOver 에서는 꾹 누르기가 어려워서 동작으로 보이기·가리기 (녹화·미러링 중이거나 앱이 비활성이면 안 보임)
            .accessibilityAction(named: reveal ? "다시 가리기" : "단어 보기") {
                if reveal { reveal = false } else if !captured && phase == .active { reveal = true }
            }
            HStack(spacing: 6) {
                Icon(captured ? "videocam-off-outline" : "finger-print", 16, captured ? C.red : (reveal ? C.green : C.mute))
                TX(captured ? "화면 녹화·미러링 중에는 보여주지 않아요" : (reveal ? "손을 떼면 다시 가려져요" : "꾹 누르고 있는 동안만 보여요"),
                   .r, 14, captured ? C.red : (reveal ? C.green : C.mute))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, compact ? 10 : 14)
            if words.isEmpty {
                TX("이 폰에서 복구 문구를 찾지 못했어요", .r, 14, C.red).padding(.top, 10)
            }
        }
    }
}

struct Warn: View {
    let text: String
    var compact = false
    var body: some View {
        HStack(alignment: .top, spacing: compact ? 8 : 10) {
            Icon("close-circle", compact ? 16 : 20, C.red)
            TX(text, .m, compact ? 13 : 15, lh: compact ? 18 : 22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 비밀번호 바꾸기

struct ChangePinView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var step = "cur"
    @State private var next = ""
    @State private var resetting = false

    var body: some View {
        Group {
            switch step {
            case "cur":
                PinPad(title: "지금 쓰는 비밀번호", length: PinVault.length, onComplete: { p in
                    let r = store.checkPin(p)
                    guard case .ok = r else { return r }
                    // 10번 넘게 틀린 뒤에 맞힌 비밀번호만으로는 바꾸지 않음 (바꾸면서 잠금이 풀리지 않게)
                    if PinVault.hardLocked {
                        return .message("비밀번호를 여러 번 틀려서 지금은 바꿀 수 없어요. 아래 '비밀번호를 잊었어요'로 본인 확인을 해주세요")
                    }
                    step = "new"
                    return .ok
                }, footer: {
                    Tap(action: { resetting = true }) {
                        TX("비밀번호를 잊었어요", .m, 14, C.sub).underline(color: C.sub).padding(12)
                    }
                    .padding(.bottom, 8)
                })
                .id("c")
            case "new":
                PinPad(title: "새 비밀번호", sub: "숫자 4자리를 입력해주세요") { p in
                    if p == store.st.pin || PinVault.matchesCurrent(p) { return .message("지금과 다른 숫자로 정해주세요") }
                    if let r = PinVault.weakReason(p) { return .message(r) }
                    next = p
                    step = "again"
                    return .ok
                }
                .id("n")
            default:
                PinPad(title: "한 번 더 입력해주세요") { p in
                    if p != next { return .message("새 비밀번호와 달라요") }
                    guard store.setPin(p) else { return .message("비밀번호를 저장하지 못했어요. 다시 시도해주세요") }
                    haptic(.success)
                    toast("비밀번호를 바꿨어요")
                    router.pop()
                    return .ok
                }
                .id("a")
            }
        }
        .background(C.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $resetting) {
            PinResetView { ok in
                resetting = false
                if ok { router.pop() }
            }
            .environmentObject(store)
        }
    }
}

// MARK: - 자동 보내기

struct SchedulesView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var del: Schedule? = nil
    @State private var delOpen = false

    var body: some View {
        let st = store.st
        let list = st.schedules.sorted { nextRun($0.day) < nextRun($1.day) }
        OScreen {
            // 자동 보내기는 아직 없음: 보낼 때마다 본인 확인이 필요해서 앱이 혼자 보낼 수 없음
            Notice(icon: "construct-outline", color: C.sub, bg: C.surface, title: "자동 보내기는 준비 중이에요",
                   text: "여기 있는 일정은 저절로 보내지지 않아요. 보낼 날이 되면 '지금 보내기'를 눌러 직접 보내주세요.")
                .padding(.bottom, 20)
            if list.isEmpty {
                Empty(icon: "repeat", title: "자동 보내기가 없어요", sub: "자동 보내기는 아직 준비 중이에요")
            } else {
                ForEach(list) { sc in
                    let n = st.nameOf(sc.to) ?? "모르는 지갑"
                    let left = daysUntil(nextRun(sc.day))
                    Card(top: 16, bottom: 16) {
                        HStack(spacing: 14) {
                            Avatar(name: n)
                            VStack(alignment: .leading, spacing: 0) {
                                TX(n, .sb, 16)
                                TX("매달 \(sc.day)일\(sc.memo.isEmpty ? "" : " · \(sc.memo)")", .r, 13, C.mute).padding(.top, 3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 0) {
                                TX(wonOf(sc.amt), .sb, 16)
                                TX(left <= 0 ? "오늘" : "\(left)일 뒤", .r, 13, left <= 3 ? C.blueText : C.mute).padding(.top, 3)
                            }
                        }
                        HStack(spacing: 8) {
                            OButton("지금 보내기", kind: .secondary, md: true) { router.sendTo(sc.to) }
                            OButton("그만 보내기", kind: .secondary, md: true) { del = sc; delOpen = true }
                        }
                        .padding(.top, 14)
                    }
                }
            }
        }
        .oSheet($delOpen, title: "자동 보내기를 멈출까요?",
                sub: del.map { "\(st.nameOf($0.to) ?? "이 지갑")에게 매달 \($0.day)일에 보내던 \(wonOf($0.amt))을 더 이상 보내지 않아요." } ?? "") {
            HStack(spacing: 8) {
                OButton("취소", kind: .secondary) { delOpen = false }
                OButton("멈추기", kind: .danger) {
                    if let d = del { store.removeSchedule(d.id) }
                    delOpen = false
                    toast("자동 보내기를 멈췄어요", "pause-circle")
                }
            }
        }
    }
}
