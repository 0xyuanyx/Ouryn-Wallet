import SwiftUI

// src/screens/Send.js — to → amount → confirm → pin → sending → done | failed
// 요청 QR 을 찍으면 받는 사람·금액·자산이 채워진 채 바로 confirm 으로

struct SendView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    let initial: PayRequest?

    @State private var step = "to"
    @State private var to: String? = nil
    @State private var q = ""
    @State private var amt: Double = 0
    @State private var prefer: String? = nil // 요청받은 달러 종류 (usdc/usdt)
    @State private var requested = false     // 금액이 요청 QR 에서 왔는지
    @State private var over = false
    @State private var memo = ""
    @State private var repeatOn = false
    @State private var nickOpen = false
    @State private var nick = ""
    @State private var bio = Bio.info()
    @State private var inner: String? = nil // "scan" | "nearby"
    @State private var started = false
    @FocusState private var memoFocus: Bool

    private var today: Int { Calendar.current.component(.day, from: Date()) }
    private var sendWillFail: Bool { false } // 실제 전송 연결 후 네트워크 오류로 대체

    var body: some View { TransferFlow(initial:initial) }

    @ViewBuilder private var liveBody: some View {
        let st = store.st
        let name = st.nameOf(to)
        let label = name ?? "처음 보내는 지갑"
        VStack(spacing: 0) {
            if step != "sending" && step != "done" && step != "failed" {
                HStack {
                    Tap(action: back) {
                        Icon(step == "to" ? "close" : "chevron-back", 26, C.text).padding(16)
                    }
                    .padding(-12)
                    .accessibilityLabel("뒤로")
                    Spacer()
                }
                .frame(height: 52)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            switch step {
            case "to": toStep(st)
            case "amount": amountStep(st, name: name, label: label)
            case "confirm": confirmStep(st, name: name, label: label)
            case "failed": failedStep
            case "pin":
                PinPad(title: "간편 비밀번호를 입력해주세요",
                       sub: "\(label)\(name != nil ? "님에게" : "로") \(wonOf(amt)) 보내기",
                       length: PinVault.length,
                       onComplete: { p in
                           let r = store.checkPin(p)
                           guard case .ok = r else { return r }
                           go("sending")
                           return .ok
                       },
                       header: { personAvatar(name, 56) },
                       footer: {
                           if store.st.bio && bio.ok {
                               BioButton(label: bio.label, icon: bio.icon) {
                                   Bio.auth("보내기 확인") { ok in if ok { go("sending") } }
                               }
                           }
                       })
            default:
                LogoStage(done: step == "done",
                          loadingTitle: "보내는 중이에요",
                          loadingSub: "\(DOLLAR_NET) 네트워크에서 확인하고 있어요",
                          doneTitle: "\(st.nameOf(to) ?? "지갑")\(st.nameOf(to) != nil ? "님에게" : "으로")\n\(wonOf(amt))을 보냈어요",
                          doneSub: memo.isEmpty ? nil : "“\(memo)”",
                          doneExtra: {
                              if repeatOn {
                                  HStack(spacing: 6) {
                                      Icon("repeat", 14, C.blueText)
                                      TX("매달 \(today)일에 자동으로 보내요", .sb, 13, C.blueText)
                                  }
                                  .padding(.horizontal, 12)
                                  .frame(height: 32)
                                  .background(Capsule().fill(C.blueSoft))
                                  .padding(.top, 14)
                              }
                          },
                          footer: {
                              VStack(spacing: 8) {
                                  if st.nameOf(to) == nil {
                                      OButton("이 지갑에 이름 붙이기", kind: .secondary, icon: "pricetag") { nick = ""; nickOpen = true }
                                  }
                                  OButton("확인") { dismiss() }
                              }
                          })
            }
        }
        .background(C.bg.ignoresSafeArea())
        .onAppear {
            if !started, let r = initial { apply(r, animated: false) }
            started = true
        }
        .fullScreenCover(item: Binding(get: { inner.map { InnerModal(id: $0) } }, set: { inner = $0?.id })) { m in
            Group {
                if m.id == "scan" {
                    ScanView(fromSend: true) { req in inner = nil; apply(req, animated: true) }
                } else {
                    NearbyView(fromSend: true) { addr in inner = nil; pick(addr) }
                }
            }
            .environmentObject(store)
            .environmentObject(router)
        }
        .oSheet($nickOpen, title: "이름을 붙여두면", sub: "다음부터 주소 대신 이름으로 찾을 수 있어요. 이름은 이 폰에만 저장돼요.") {
            Field(text: $nick, placeholder: "예: 민지, 월세, 거래소", autoFocus: true, maxLength: 12)
            OButton("저장", disabled: nick.trimmingCharacters(in: .whitespaces).isEmpty) {
                let n = nick.trimmingCharacters(in: .whitespaces)
                if let t = to { store.setContact(t, n) }
                nickOpen = false
                toast("'\(n)'(으)로 저장했어요")
            }
            .padding(.top, 12)
        }
    }

    // MARK: 단계 이동

    private func go(_ s: String) {
        step = s
        if s == "sending" {
            after(0.9) {
                guard let t = to else { return }
                let m = memo.trimmingCharacters(in: .whitespaces)
                if sendWillFail {
                    store.sendFailed(to: t, amt: amt, memo: m, prefer: prefer)
                    haptic(.error)
                    step = "failed"
                    return
                }
                store.send(to: t, amt: amt, memo: m, prefer: prefer)
                if repeatOn { store.addSchedule(to: t, amt: amt, day: today, memo: m) }
                step = "done"
            }
        }
    }

    private func back() {
        if step == "to" || step == "done" { dismiss(); return }
        if step == "confirm" { requested = false }
        step = ["amount": "to", "confirm": "amount", "pin": "confirm"][step] ?? "to"
    }

    /// QR·붙여넣기·다시 보내기로 받은 요청 채우기
    private func apply(_ r: PayRequest, animated: Bool) {
        if animated { haptic(.select) }
        to = r.to
        prefer = r.asset
        if let u = r.usd, u > 0 {
            amt = u
            requested = true
            step = "confirm"
        } else {
            requested = false
            step = "amount"
        }
    }

    private func pick(_ a: String) {
        haptic(.select)
        to = a
        prefer = nil
        requested = false
        step = "amount"
    }

    private func paste() {
        let s = UIPasteboard.general.string ?? ""
        if let r = parsePay(s) { apply(r, animated: true) }
        else { toast("복사한 지갑 주소가 없어요", "clipboard-outline") }
    }

    // MARK: 받는 사람

    private func toStep(_ st: AppState) -> some View {
        var seen = Set<String>()
        var recent: [String] = []
        for t in st.tx where (t.type == .send || t.type == .receive) {
            if let a = t.addr, !seen.contains(a) { seen.insert(a); recent.append(a) }
        }
        recent = Array(recent.prefix(8))
        let query = q.trimmingCharacters(in: .whitespaces)
        let contacts = st.contacts
            .filter { query.isEmpty || $0.value.name.contains(query) || $0.key.lowercased().contains(query.lowercased()) }
            .sorted { $0.key < $1.key }

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TX("누구에게 보낼까요?", .b, 26).padding(.top, 4).padding(.bottom, 20)
                Field(text: $q, placeholder: "이름 또는 지갑 주소")
                if isAddr(q) {
                    ListItem(left: AnyView(Avatar(icon: "wallet", color: C.surface3)), title: "이 지갑으로 보내기", sub: short(query), chevron: true) {
                        pick(query)
                    }
                    .padding(.top, 8)
                }

                if q.isEmpty {
                    HStack(spacing: 8) {
                        Tile(icon: "scan", label: "QR 찍기") { inner = "scan" }
                        Tile(icon: "radio", label: "가까이") { inner = "nearby" }
                        Tile(icon: "clipboard", label: "붙여넣기") { paste() }
                    }
                    .padding(.top, 14)

                    if !recent.isEmpty {
                        SectionTitle(title: "최근", bottom: 12).padding(.top, 28)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(recent, id: \.self) { a in
                                    let n = st.nameOf(a)
                                    Tap(action: { pick(a) }) {
                                        VStack(spacing: 0) {
                                            personAvatar(n, 56)
                                            TX(n ?? String(short(a).prefix(4)), .m, 13, C.sub, lines: 1).padding(.top, 6)
                                        }
                                        .frame(width: 60)
                                    }
                                }
                            }
                        }
                    }
                }

                SectionTitle(title: "주소록").padding(.top, 28)
                ForEach(contacts, id: \.key) { a, c in
                    ListItem(left: AnyView(Avatar(name: c.name)), title: c.name, sub: short(a)) { pick(a) }
                }
                if contacts.isEmpty && !isAddr(q) {
                    TX("찾는 사람이 없어요. 지갑 주소를 붙여넣어 보세요.", .r, 14, C.mute, align: .center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: 금액

    private func amountStep(_ st: AppState, name: String?, label: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                personAvatar(name, 32)
                (tt(label, .sb, 18) + tt(name != nil ? "님에게" : "로", .r, 18, C.sub))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            AmountEntry(max: st.walletTotal) { v, o in amt = v; over = o }
            OButton("다음", disabled: !(amt > 0) || over) { step = "confirm" }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    // MARK: 확인

    private func confirmStep(_ st: AppState, name: String?, label: String) -> some View {
        let bal = st.walletTotal
        let short1 = amt > bal + 1e-9
        let plan = sendPlan(st.wallet, amt, prefer: prefer)
        let mixed = plan.count > 1
        let offRequest = prefer != nil && plan.contains { $0.asset != prefer }
        return VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        personAvatar(name, 64)
                        if requested {
                            Chip(label: "요청받은 금액이에요", soon: true).padding(.top, 14)
                        }
                        TX("\(label)\(name != nil ? "님에게" : "로")\n\(wonOf(amt))을 보낼게요", .b, 24, lh: 34, align: .center).padding(.top, requested ? 10 : 18)
                        TX(dollar(amt), .r, 15, C.sub).padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                    if name == nil {
                        Notice(icon: "alert-circle", color: C.red, bg: C.redSoft, title: "처음 보내는 지갑이에요",
                               text: "보낸 돈은 되돌릴 수 없어요. 주소가 맞는지 받는 분과 한 번 더 확인해주세요.", mono: to)
                            .padding(.top, 24)
                    }
                    if short1 {
                        Notice(icon: "wallet", color: C.red, bg: C.redSoft, title: "보낼 수 있는 돈이 모자라요",
                               text: "지금 보낼 수 있는 돈은 \(wonOf(bal))이에요. 거래소에서 가져오거나 금액을 줄여주세요.")
                            .padding(.top, 12)
                    } else if offRequest {
                        Notice(icon: "swap-horizontal", color: C.amber, bg: C.amberSoft, title: "요청한 돈은 \(assetFullName(prefer ?? "usdc"))예요",
                               text: "\(assetFullName(prefer ?? "usdc"))가 모자라서 다른 달러가 섞여 가요. 받는 분에게 괜찮은지 확인해주세요.")
                            .padding(.top, 12)
                    } else if mixed {
                        Notice(icon: "git-branch", color: C.sub, bg: C.surface, title: "두 가지 달러로 나눠 보내요",
                               text: "서클 달러가 모자라서 테더 달러를 더해요. 받는 분 지갑에는 두 번에 나눠 들어가요.")
                            .padding(.top, 12)
                    }

                    VStack(spacing: 0) {
                        InfoRow(label: "받는 분", value: name ?? short(to))
                        InfoRow(label: "보내는 돈", value: short1 ? "-" : plan.map { "\(assetFullName($0.asset)) \(dollar($0.amt))" }.joined(separator: "\n"))
                        InfoRow(label: "네트워크", value: DOLLAR_NET)
                        InfoRow(label: "받는 분이 받는 돈", value: wonOf(amt))
                        InfoRow(label: "네트워크 수수료", value: "몇 원 이하 (예상)", valueColor: C.sub)
                        InfoRow(label: "보낸 뒤 남는 돈", value: short1 ? "-" : wonOf(bal - amt), last: true)
                    }
                    .padding(.horizontal, 18)
                    .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
                    .padding(.top, 20)

                    HStack(spacing: 10) {
                        Icon("chatbubble-ellipses-outline", 18, C.mute)
                        ZStack(alignment: .leading) {
                            if memo.isEmpty { TX("받는 분에게 메모 남기기 (선택)", .m, 15, C.mute).allowsHitTesting(false) }
                            TextField("", text: $memo)
                                .font(pfont(.m, 15))
                                .foregroundColor(C.text)
                                .tint(C.text)
                                .focused($memoFocus)
                                .onChange(of: memo) { _, v in if v.count > 20 { memo = String(v.prefix(20)) } }
                        }
                        // RN 의 TextInput 처럼 칸 전체를 눌러도 메모를 쓸 수 있게 (flex:1, height:'100%')
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { memoFocus = true }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
                    .padding(.top, 12)

                    HStack(spacing: 10) {
                        Icon("repeat", 18, repeatOn ? C.blueText : C.mute)
                        VStack(alignment: .leading, spacing: 0) {
                            TX("매달 자동으로 보내기", .m, 15)
                            TX("매달 \(today)일 아침 9시에 같은 금액을 보내요", .r, 12, C.mute).padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        OSwitch(isOn: Binding(get: { repeatOn }, set: { v in haptic(.select); repeatOn = v }))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            OButton("보내기", disabled: short1 || !(amt > 0)) { if store.st.pinOnSend { step = "pin" } else { go("sending") } }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    // MARK: 실패

    private var failedStep: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(C.redSoft)
                Icon("alert-circle", 48, C.red)
            }
            .frame(width: 104, height: 104)
            TX("보내지 못했어요", .b, 24, align: .center).padding(.top, 28)
            TX("돈은 빠져나가지 않았어요.\n네트워크가 붐비면 생길 수 있어요. 잠시 뒤 다시 해주세요.", .r, 15, C.sub, lh: 22, align: .center)
                .padding(.top, 10)
                .padding(.horizontal, 32)
            TX("이 시도는 내역에 '실패'로 남아요", .r, 13, C.mute, align: .center).padding(.top, 14)
            Spacer()
            Spacer()
            VStack(spacing: 8) {
                OButton("다시 보내기") { go("sending") }
                OButton("닫기", kind: .secondary) { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
}

/// 확인 화면의 안내 상자
struct Notice: View {
    let icon: String
    let color: Color
    let bg: Color
    let title: String
    let text: String
    var mono: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, 20, color)
            VStack(alignment: .leading, spacing: 0) {
                TX(title, .sb, 14, color == C.sub ? C.text : color)
                TX(text, .r, 13, C.sub, lh: 19).padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
                if let m = mono {
                    Text(m)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(C.text)
                        .lineSpacing(4)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(bg))
    }
}

private struct InnerModal: Identifiable { let id: String }

private struct Tile: View {
    let icon: String
    let label: String
    let onPress: () -> Void

    var body: some View {
        Tap(haptics: .light, action: onPress) {
            VStack(spacing: 8) {
                Icon(icon, 24, C.text)
                TX(label, .m, 14, C.sub)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .edge(18, C.surface)
        }
    }
}

// 실제 서명(보내기)이 연결되기 전 화면 — 읽은 QR 요청은 보여줌
struct SendLockedView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let req: PayRequest?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Tap(action: { dismiss() }) { Icon("close", 26, C.text).padding(16) }
                    .padding(-12)
                    .accessibilityLabel("닫기")
                Spacer()
            }
            .frame(height: 52)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            Spacer()
            ZStack { Circle().fill(C.surface); Icon("lock-closed", 40, C.text) }
                .frame(width: 96, height: 96)
            TX("보내기는 곧 열려요", .b, 24, align: .center).padding(.top, 24)
            TX("지금은 실제 지갑 잔액을 보여주기만 해요.\n서명과 수수료 처리를 붙인 다음 열게요.", .r, 15, C.sub, lh: 22, align: .center)
                .padding(.top, 10)
                .padding(.horizontal, 32)
            if let r = req {
                VStack(spacing: 0) {
                    InfoRow(label: "받는 분", value: store.st.nameOf(r.to) ?? short(r.to))
                    if let u = r.usd {
                        InfoRow(label: "요청 금액", value: "\(assetFullName(r.asset ?? "usdc")) \(dollar(u))")
                        InfoRow(label: "원화로", value: "약 \(wonOf(u))", last: true)
                    } else {
                        InfoRow(label: "요청 금액", value: "정하지 않음", valueColor: C.mute, last: true)
                    }
                }
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
                .padding(.horizontal, 24)
                .padding(.top, 28)
                TX("QR은 제대로 읽혔어요", .r, 13, C.green).padding(.top, 10)
            }
            Spacer()
            Spacer()
            OButton("닫기", kind: .secondary) { dismiss() }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(C.bg.ignoresSafeArea())
    }
}
