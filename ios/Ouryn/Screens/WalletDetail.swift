import SwiftUI

// 지갑 상세 · 주소 전체 보기 · 내 통장 표시 · 코인 내역 전체 보기

// MARK: - 주소를 4글자씩

/// "0x7Bd29aF1…" → ("0x", ["7Bd2", "9aF1", …]) — 숫자용 grouped4 와 다른 이름
func addrGroups(_ raw: String) -> (prefix: String, groups: [String]) {
    let a = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let pre = a.hasPrefix("0x") ? "0x" : ""
    let body = Array(a.dropFirst(pre.count))
    var out: [String] = []
    var i = 0
    while i < body.count {
        out.append(String(body[i..<min(i + 4, body.count)]))
        i += 4
    }
    return (pre, out)
}

/// 주소 전체를 고정폭 4글자 묶음으로 — 첫 묶음과 끝 묶음만 파랑 (앞뒤만 같은 가짜 주소와 구분)
struct AddressGroups: View {
    let address: String
    var size: CGFloat = 17

    var body: some View {
        let g = addrGroups(address)
        HStack(alignment: .top, spacing: 10) {
            if !g.prefix.isEmpty {
                Text(g.prefix).font(.system(size: size, weight: .medium, design: .monospaced)).foregroundColor(C.faint)
            }
            // 한 줄에 5묶음씩 가로로 · 묶음 안에서는 절대 줄바꿈하지 않고, 자리가 모자라면 글자만 살짝 줄임
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(stride(from: 0, to: g.groups.count, by: 5)), id: \.self) { start in
                    HStack(spacing: 8) {
                        ForEach(start..<min(start + 5, g.groups.count), id: \.self) { i in
                            let edge = i == 0 || i == g.groups.count - 1
                            Text(g.groups[i])
                                .font(.system(size: size, weight: edge ? .bold : .medium, design: .monospaced))
                                .foregroundColor(edge ? C.addr : Color(hex: "#D8D8DC"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if min(start + 5, g.groups.count) - start < 5 {
                            ForEach(0..<(5 - (min(start + 5, g.groups.count) - start)), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(address)
    }
}

// MARK: - 내 통장 표시

/// 내 통장 아바타 — 사람 글자 대신 Ouryn 로고 (원 안 비율은 하단 O 버튼과 같게)
struct MineAvatar: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(C.surface)
            Circle().strokeBorder(C.surface3, lineWidth: 1)
            Logo(size: size * LOGO_IN_CIRCLE)
        }
        .frame(width: size, height: size)
    }
}

/// 이름 옆 작은 파란 배지
struct MineTag: View {
    var text = "내 통장"
    var body: some View {
        TX(text, .b, 11, Color(hex: "#9ED3FF"))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(C.addr.opacity(0.14)))
            .fixedSize()
    }
}

extension AppState {
    /// 그 주소가 내 통장이면 배지 글자 (테스트 통장이면 '· 테스트')
    func mineTagText(_ own: OwnAccount) -> String {
        accountList.first { $0.id == own.id }?.isTest == true ? "내 통장 · 테스트" : "내 통장"
    }
}

// MARK: - 지갑 상세 (이름 없는 주소 · 주소록 상세와 같은 틀)

struct WalletDetailView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.openURL) private var openURL
    let address: String
    let network: String
    @State private var naming = false
    @State private var text = ""

    var body: some View {
        let id = SavedRecipient(network: network, address: address, name: "").id
        // 이름이 붙어 있으면 그대로 주소록 상세
        if let r = (store.st.savedRecipients ?? []).first(where: { $0.id == id }) {
            SavedRecipientDetailView(recipient: r)
        } else {
            unknown
        }
    }

    private var unknown: some View {
        let st = store.st
        let n = WalletNetwork(rawValue: network)
        let own = st.ownAccount(address: address, net: network)
        let txs = st.tx.filter { $0.network == network && sameAddr($0.addr) }.sorted { $0.ts > $1.ts }
        return OScreen(pad: 24) {
            HStack(spacing: 14) {
                Group {
                    if own != nil { MineAvatar(size: 56) } else { Avatar(icon: "help", color: C.surface3, size: 56) }
                }
                .networkBadge(network, size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TX(own?.title ?? "모르는 지갑", .b, 24, lines: 1)
                        if let own { MineTag(text: st.mineTagText(own)) }
                    }
                    HStack(spacing: 6) {
                        CoinLogo(network: network, size: 14)
                        TX(Testnet.on ? (n.map(Testnet.name) ?? network) : "\(network) 네트워크", .sb, 12, Color(hex: "#D8D8DC"))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(C.surface2))
                }
            }

            Tap(scale: 0.99, action: {
                UIPasteboard.general.string = address
                haptic(.success)
                toast("주소를 복사했어요")
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TX("지갑 주소 · 전체", .sb, 12, C.mute)
                        Spacer()
                        HStack(spacing: 4) { Icon("copy-outline", 14, C.sub); TX("누르면 복사", .sb, 12, C.sub) }
                    }
                    AddressGroups(address: address)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
            }
            .accessibilityLabel("지갑 주소 복사")
            .padding(.top, 22)

            if let url = n?.explorer(address: address) {
                Tap(scale: 0.99, action: { openURL(url) }) {
                    HStack {
                        TX("탐색기에서 이 주소 보기", .sb, 14)
                        Spacer()
                        Icon("open-outline", 14, C.mute)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14).fill(C.surface))
                }
                .padding(.top, 8)
            }

            if own == nil {
                HStack(alignment: .top, spacing: 8) {
                    Icon("shield-checkmark-outline", 15, C.mute)
                    TX("앞뒤만 같은 가짜 주소로 돈을 보내게 하는 수법이 있어요. 보내기 전에는 가운데까지 전부 맞는지 확인하세요.",
                       .r, 12, C.mute, lh: 18)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
            }

            TX("이 지갑과의 거래 · \(txs.count)", .b, 14, C.sub).padding(.top, 22)
            if txs.isEmpty {
                TX("이 주소와는 처음이에요", .r, 14, C.mute).padding(.vertical, 16)
            }
            ForEach(txs) { t in TxRow(t: t) { router.push(.txDetail(t.id)) } }
        } footer: {
            OButton("이름 붙이기") { text = ""; naming = true }
        }
        .oSheet($naming, title: "이름 붙이기", sub: nameSub) {
            VStack(alignment: .leading, spacing: 8) {
                TX("이 주소예요", .sb, 12, C.mute)
                AddressGroups(address: address, size: 14)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(C.surface2))
            Field(text: $text, placeholder: "예: 민지, 월세, 거래소", autoFocus: true, maxLength: 12).padding(.top, 16)
            OButton("저장", disabled: text.trimmingCharacters(in: .whitespaces).isEmpty) {
                let v = text.trimmingCharacters(in: .whitespaces)
                store.saveRecipient(network: network, address: address, name: v)
                naming = false
                toast("'\(v)'(으)로 저장했어요")
            }
            .padding(.top, 16)
        }
    }

    private var nameSub: String {
        let evm = WalletNetwork(rawValue: network)?.isEVM ?? false
        return evm ? "\(network) 네트워크의 이 주소에만 붙어요. 다른 0x 네트워크에서 같은 주소를 쓰면 거기선 따로 붙여요."
                   : "\(network) 네트워크의 이 주소에 붙어요. 이름은 이 폰에만 저장돼요."
    }

    private func sameAddr(_ a: String?) -> Bool {
        guard let a else { return false }
        return (WalletNetwork(rawValue: network)?.isEVM ?? false) ? a.lowercased() == address.lowercased() : a == address
    }
}

// MARK: - 코인 내역 전체 보기 (내역 탭의 날짜 묶음 그대로)

struct CoinHistoryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let id: String
    @State private var f = "all"

    var body: some View {
        let st = store.st
        let all = st.tx.filter { $0.assetId == id }.sorted { $0.ts > $1.ts }
        let shown = all.filter { f == "in" ? $0.type == .receive : (f == "out" ? $0.type == .send : true) }
        let done = all.filter { $0.status == .done }
        let inQty = done.filter { $0.type == .receive }.reduce(0) { $0 + $1.quantity }
        let outQty = done.filter { $0.type == .send }.reduce(0) { $0 + $1.quantity }
        var sections: [(String, [Tx])] = []
        for t in shown {
            let k = dayLabel(t.ts)
            if let i = sections.firstIndex(where: { $0.0 == k }) { sections[i].1.append(t) } else { sections.append((k, [t])) }
        }
        let name = assetMeta(id).name
        return ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    CoinLogo(asset: id, size: 28)
                    TX("\(name) 내역", .b, 26)
                }
                .padding(.top, 12)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        TX("받은 \(name)", .r, 13, C.mute)
                        TX(st.hide ? "••••" : "+" + qtyText(inQty), .b, 19, C.green).padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(C.line).frame(width: 1).padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 0) {
                        TX("보낸 \(name)", .r, 13, C.mute)
                        TX(st.hide ? "••••" : "-" + qtyText(outQty), .b, 19).padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
                .padding(.top, 18)
                HStack(spacing: 8) {
                    ForEach([("all", "전체"), ("in", "받은 것"), ("out", "보낸 것")], id: \.0) { k, l in
                        Pill(label: l, active: f == k) { f = k }
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 4)
                if sections.isEmpty { Empty(title: "해당하는 내역이 없어요") }
                ForEach(sections, id: \.0) { title, data in
                    TX(title, .m, 13, C.mute).padding(.top, 22).padding(.bottom, 2)
                    ForEach(data) { t in TxRow(t: t) { router.push(.txDetail(t.id)) } }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(C.bg.ignoresSafeArea())
    }
}
