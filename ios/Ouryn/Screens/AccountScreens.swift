import SwiftUI

// 통장 · 지갑 화면 (캔버스 W1~W6)
// AccountSheet: 홈 위 통장 칩 → 통장 고르기 (W2)
// AddWalletView: 지갑 추가하기 (W3) → ImportWalletView: 12단어 → 자동으로 찾기 → 가져오기 (W4)

// MARK: - 작은 조각

/// 지갑 표시 — Ouryn 지갑은 로고, 나머지는 이름 첫 글자
struct WalletMark: View {
    let wallet: WalletBox?
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            if wallet?.isMain ?? true {
                Circle().fill(C.surface)
                Circle().strokeBorder(C.surface3, lineWidth: 1)
                Logo(size: size * LOGO_IN_CIRCLE)
            } else {
                Circle().fill(C.surface3)
                TX(String((wallet?.name ?? "?").prefix(1)).uppercased(), .b, size * 0.46)
            }
        }
        .frame(width: size, height: size)
    }
}

struct StateChip: View {
    let text: String
    let ok: Bool
    var body: some View {
        TX(text, .sb, 12, ok ? C.green : C.amber)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(ok ? C.greenSoft : C.amber.opacity(0.14)))
            .fixedSize()
    }
}

// MARK: - 통장 고르기 (W2)

struct AccountSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var renaming: Account? = nil
    @State private var adding: String? = nil   // 통장 추가 고르는 중인 지갑
    @State private var removing: Account? = nil
    @State private var newName = ""
    @State private var renamingWallet: WalletBox? = nil
    @State private var walletNewName = ""

    private func money(_ usd: Double) -> String { store.st.hide ? "••••••" : wonOf(usd) }

    var body: some View {
        let st = store.st
        let rows = st.accountList.count + st.walletList.count * 2
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                TX("통장", .b, 22)
                Spacer()
                (tt("전체 합계 ", .r, 13, C.sub) + tt(money(st.allAccountsUsd), .b, 13))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 18)
            .alert("통장 이름", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("이름", text: $newName)
                Button("취소", role: .cancel) { renaming = nil }
                Button("저장") {
                    if let r = renaming { store.renameAccount(r.id, newName) }
                    renaming = nil
                }
            }

            if rows > 9 {
                ScrollView(showsIndicators: false) { groups }
                    .frame(height: UIScreen.main.bounds.height * 0.52)
            } else {
                groups
            }

            Tap(action: {
                router.accountSheet = false
                after(0.35) { router.present(.addWallet) }
            }) {
                HStack {
                    TX("지갑 추가하기", .sb, 15)
                    Spacer()
                    Icon("chevron-forward", 16, C.faint)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(C.surface3, lineWidth: 1))
            }
            .padding(.top, 14)

            TX("통장을 길게 누르면 이름 바꾸기 · 지우기", .r, 12, Color(hex: "#6B6B76"))
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .alert("지갑 이름", isPresented: Binding(get: { renamingWallet != nil }, set: { if !$0 { renamingWallet = nil } })) {
                    TextField("이름", text: $walletNewName)
                    Button("취소", role: .cancel) { renamingWallet = nil }
                    Button("저장") {
                        if let r = renamingWallet { store.renameWallet(r.id, walletNewName) }
                        renamingWallet = nil
                    }
                }
        }
        .alert(removing.map { "‘\($0.name)’ 통장을 지울까요?" } ?? "",
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("취소", role: .cancel) { removing = nil }
            Button("지우기", role: .destructive) {
                if let r = removing { store.removeAccount(r.id); haptic(.success); toast("통장을 지웠어요") }
                removing = nil
            }
        } message: {
            if let r = removing { Text(removeMessage(r)) }
        }
    }

    private func removeMessage(_ r: Account) -> String {
        if r.isTest { return "테스트넷 잔액·내역만 목록에서 사라져요." }
        let back = "나중에 '통장 추가'를 하면 같은 통장으로 다시 돌아와요."
        if store.st.totalUsd(r) > 0 { return "잔액이 남아 있어요. 목록에서만 빠지고 돈은 블록체인에 그대로 있어요. " + back }
        return "목록에서만 빠져요. " + back
    }

    private var groups: some View {
        let st = store.st
        return VStack(spacing: 10) {
            ForEach(st.walletList) { w in
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        WalletMark(wallet: w, size: 28)
                        HStack(spacing: 0) {
                            TX(w.name, .b, 14, Color(hex: "#D8D8DC"), lines: 1)
                            Tap(scale: 0.9, action: { walletNewName = w.name; renamingWallet = w }) {
                                Icon("pencil", 14, C.mute).frame(width: 36, height: 28)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        let ok = st.walletBackedUp(w.id)
                        StateChip(text: ok ? "✓ 12단어 적어둠" : (w.isMain ? "⚠ 아직 안 적음" : "⚠ 12단어 미작성"), ok: ok)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    ForEach(st.accountsIn(w.id)) { a in
                        row(a)
                    }

                    if adding == w.id {
                        // 통장 추가: 일반 / 테스트
                        HStack(spacing: 8) {
                            addChoice("일반 통장", sub: "백업 필요 없어요", icon: "add") { add(w.id, test: false) }
                            addChoice("테스트 통장", sub: "테스트넷 · 실제 돈 아님", icon: "flask") { add(w.id, test: true) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    } else {
                        Tap(action: { withAnimation(.easeOut(duration: 0.2)) { adding = w.id } }) {
                            HStack(spacing: 8) {
                                Icon("add", 16, C.sub)
                                tt("통장 추가", .sb, 14, C.sub) + tt(" · 백업 필요 없어요", .r, 14, Color(hex: "#6B6B76"))
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .background(RoundedRectangle(cornerRadius: 20).fill(C.surface2))
            }
        }
    }

    private func addChoice(_ title: String, sub: String, icon: String, action: @escaping () -> Void) -> some View {
        Tap(scale: 0.97, action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Icon(icon, 16, C.text)
                TX(title, .sb, 14).padding(.top, 4)
                TX(sub, .r, 11, C.mute, lines: 1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(C.surface3))
        }
    }

    private func add(_ wallet: String, test: Bool) {
        adding = nil
        Task { @MainActor in
            guard let a = await store.addAccount(walletId: wallet, test: test) else { toast("통장을 만들지 못했어요", "alert-circle"); return }
            haptic(.success)
            if test {
                // 테스트 통장은 만들고 바로 들어가서 토큰 받기로
                store.switchAccount(a.id)
                router.accountSheet = false
                after(0.35) { router.push(.faucet) }
            } else {
                toast("새 통장을 만들었어요 · 새로 적을 건 없어요", "add-circle")
            }
        }
    }

    private func row(_ a: Account) -> some View {
        let st = store.st
        let on = a.id == st.activeId
        return Tap(scale: 0.985, action: {
            store.switchAccount(a.id)
            router.accountSheet = false
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        TX(a.name, .sb, 16, lines: 1)
                        if a.isTest {
                            TX("테스트넷", .sb, 11, C.down)
                                .padding(.horizontal, 6)
                                .frame(height: 20)
                                .background(Capsule().fill(C.down.opacity(0.16)))
                        }
                    }
                    TX(a.isTest ? "실제 돈 아님 · " + st.heldLabel(a) : st.heldLabel(a), .r, 12, C.mute, lines: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TX(a.isTest ? "" : money(st.totalUsd(a)), .sb, 15)
                Group {
                    if on { Icon("checkmark", 20, C.text) } else { Color.clear }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .background(RoundedRectangle(cornerRadius: 14).fill(on ? Color(hex: "#26262B") : Color.clear))
        }
        .contextMenu {
            Button { newName = a.name; renaming = a } label: { Label("이름 바꾸기", systemImage: "pencil") }
            Button {
                UIPasteboard.general.string = a.addrs.solana
                toast("솔라나 주소를 복사했어요")
            } label: { Label("솔라나 주소 복사", systemImage: "doc.on.doc") }
            if store.canRemove(a) {
                Button(role: .destructive) { removing = a } label: { Label("통장 지우기", systemImage: "trash") }
            }
        }
    }
}

// MARK: - 지갑 추가하기 (W3)

struct AddWalletFlow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router

    var body: some View {
        NavigationStack {
            AddWalletView()
                .toolbar(.hidden, for: .navigationBar)
        }
        .tint(C.text)
    }
}

struct AddWalletView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var confirmNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Tap(action: { dismiss() }) {
                Icon("close", 26, C.text).frame(width: 44, height: 44)
            }
            .padding(.leading, -12)
            .accessibilityLabel("닫기")

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TX("지갑 추가하기", .b, 26).padding(.top, 14)
                    TX("지갑은 12단어가 따로 있는 묶음이에요. 은행을 하나 더 만드는 것과 같아요.", .r, 15, C.sub, lh: 22)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    choice(icon: "download-outline", title: "다른 앱 지갑 가져오기",
                           sub: "Phantom · MetaMask · Trust Wallet 등에서 쓰던 12단어로 가져와요") { importing = true }
                        .padding(.top, 26)
                    choice(icon: "add", title: "새 지갑 만들기",
                           sub: "12단어가 하나 더 생겨요. 처음처럼 종이에 적고 확인해야 쓸 수 있어요") { confirmNew = true }
                        .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 0) {
                        TX("통장만 하나 더 필요한가요?", .b, 14)
                        (tt("결제용·저축용처럼 나누기만 할 거라면 지갑 말고 ", .r, 13, C.sub) + tt("통장 추가", .b, 13)
                         + tt("가 더 간단해요. 지금 12단어 그대로라 새로 적을 게 없어요.", .r, 13, C.sub))
                            .lineSpacing(lineGap(13, 19))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                        Tap(action: addAccountHere) {
                            TX("통장 추가하기", .sb, 13)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(Capsule().fill(C.surface3))
                        }
                        .padding(.top, 12)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(C.line, lineWidth: 1))
                    .padding(.top, 22)
                }
            }

            TX("지갑을 나눠두면, 12단어 하나를 누가 알게 돼도\n그 지갑에 있는 돈만 위험하고 다른 지갑 돈은 안전해요.",
               .r, 12, Color(hex: "#6B6B76"), lh: 18, align: .center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .background(C.bg.ignoresSafeArea())
        .navigationDestination(isPresented: $importing) {
            ImportWalletView().toolbar(.hidden, for: .navigationBar)
        }
        .oSheet($confirmNew, title: "새 지갑을 만들까요?",
                sub: "새 12단어가 생기고, 그 지갑의 첫 통장으로 바뀌어요. 바로 이어서 종이에 적고 두 단어를 확인해요.") {
            HStack(spacing: 8) {
                OButton("취소", kind: .secondary) { confirmNew = false }
                OButton("만들기") {
                    confirmNew = false
                    after(0.3) { createNew() }
                }
            }
        }
    }

    private func choice(icon: String, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Tap(scale: 0.985, action: action) {
            HStack(spacing: 14) {
                ZStack { Circle().fill(C.surface3); Icon(icon, 22, C.text) }
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    TX(title, .b, 17)
                    TX(sub, .r, 13, C.sub, lh: 19).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon("chevron-forward", 16, C.faint)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
        }
    }

    private func addAccountHere() {
        let w = store.st.currentWallet?.id ?? "main"
        Task { @MainActor in
            guard let a = await store.addAccount(walletId: w) else { toast("통장을 만들지 못했어요", "alert-circle"); return }
            store.switchAccount(a.id)
            haptic(.success)
            dismiss()
            after(0.4) { toast("새 통장을 만들었어요 · 새로 적을 건 없어요", "add-circle") }
        }
    }

    private func createNew() {
        guard store.createWallet(), let w = store.st.currentWallet else {
            toast("지갑을 만들지 못했어요", "alert-circle"); return
        }
        dismiss()
        after(0.5) { router.push(.walletPhrase(w.id)) }
    }
}

// MARK: - 다른 앱 지갑 가져오기 (W4)

struct ImportWalletView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var step = "words"   // words | search | found
    @State private var words = ""
    @State private var bad: String? = nil
    @State private var scan: WalletScan? = nil
    @State private var name = "가져온 지갑"
    @State private var saving = false
    @State private var findingMore = false

    private var list: [String] { WalletKeys.normalize(words).split(separator: " ").map(String.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step != "search" {
                Tap(action: {
                    if step == "found" { step = "words"; scan = nil } else { dismiss() }
                }) {
                    Icon("chevron-back", 22, C.text).frame(width: 44, height: 44)
                }
                .padding(.leading, -12)
                .accessibilityLabel("뒤로")
            }
            switch step {
            case "search": searching
            case "found": found
            default: input
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(C.bg.ignoresSafeArea())
    }

    // 1. 12단어
    private var input: some View {
        let l = list
        let unknown = l.filter { !WalletKeys.isValidWord($0) }
        let countOk = l.count == 12 || l.count == 24
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TX("쓰던 12단어(또는 24단어)를\n입력해주세요", .b, 26, lh: 36).padding(.top, 10)
                    TX("Phantom·MetaMask 방식과 Trust Wallet·Ledger 방식의 경로를 차례로 확인해요. 입력한 단어는 이 폰 밖으로 나가지 않아요.",
                       .r, 15, C.sub, lh: 22)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    TX("비밀 문구(passphrase · 25번째 단어)를 함께 쓰던 지갑은 아직 가져올 수 없어요. 하드웨어 지갑(Ledger 등)의 단어를 폰에 입력하면 하드웨어 지갑의 보호를 잃으니, 그 돈은 하드웨어 지갑으로 관리하세요.",
                       .r, 13, C.mute, lh: 19)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    Field(text: $words, placeholder: "apple banana …", mono: true).padding(.top, 24)
                    HStack {
                        TX("\(l.count)/\(l.count > 12 ? 24 : 12)", .m, 13, countOk ? C.green : C.mute)
                        Spacer()
                        Tap(action: {
                            if let t = UIPasteboard.general.string {
                                words = WalletKeys.normalize(t); bad = nil
                                UIPasteboard.general.items = []   // 12단어가 클립보드에 남지 않게
                            }
                        }) {
                            TX("붙여넣기", .m, 13, C.sub).padding(.vertical, 6)
                        }
                    }
                    .padding(.top, 10)
                    if !unknown.isEmpty {
                        TX("목록에 없는 단어가 있어요: \(unknown.prefix(3).joined(separator: ", "))", .r, 13, C.red).padding(.top, 6)
                    } else if let bad {
                        TX(bad, .r, 13, C.red, lh: 19).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            OButton("지갑 찾기", disabled: !countOk || !unknown.isEmpty) { start() }
        }
    }

    private func start() {
        let w = WalletKeys.normalize(words)
        guard WalletKeys.isValid(w) else {
            bad = "단어는 맞는데 순서나 조합이 맞지 않아요. 적어둔 종이를 다시 확인해주세요."; haptic(.error); return
        }
        if let same = store.existingWallet(words: w) {
            bad = "이미 이 폰에 있는 지갑이에요 (\(same))."; haptic(.error); return
        }
        bad = nil
        hideKeyboard()
        step = "search"
        Task {
            let r = await store.discover(words: w)
            await MainActor.run {
                scan = r
                step = "found"
                haptic(.success)
            }
        }
    }

    // 2. 찾는 중
    private var searching: some View {
        VStack(spacing: 0) {
            Spacer()
            LogoMark(status: .loading, size: 88)
            TX("쓰던 통장을 찾고 있어요", .b, 22).padding(.top, 28)
            TX("Phantom·MetaMask·Trust 방식을 차례로 확인해요", .r, 15, C.sub).padding(.top, 8)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // 3. 찾았어요
    private var found: some View {
        let accs = scan?.accounts ?? []
        let any = accs.contains { $0.usd > 0 || !$0.nets.isEmpty }
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TX("지갑을 찾았어요", .b, 26).padding(.top, 10)
                    TX(any ? "이 12단어로 쓰던 통장 \(accs.count)개예요. 그대로 가져올게요."
                           : "쓰던 기록은 없어요. 빈 통장 하나로 가져올게요.", .r, 15, C.sub, lh: 22)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    if let missed = scan?.unchecked, !missed.isEmpty {
                        // 조회 실패를 빈 통장으로 치지 않음 → 놓쳤을 수 있다고 알리고 다시 찾게
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Icon("alert-circle", 16, C.amber)
                                TX("일부 네트워크를 확인하지 못했어요", .sb, 13, C.amber)
                            }
                            TX("통장 \(missed.count)개의 잔액이나 거래 기록을 읽지 못했어요. 쓰던 통장을 놓쳤을 수 있으니 다시 찾아보세요.",
                               .r, 13, Color(hex: "#D8D8DC"), lh: 19)
                                .fixedSize(horizontal: false, vertical: true)
                            Tap(action: { start() }) {
                                TX("다시 찾기", .sb, 13, C.text).underline(color: C.text).padding(.vertical, 4)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(C.amber.opacity(0.10)))
                        .padding(.top, 16)
                    } else {
                        HStack(spacing: 8) {
                            Icon("checkmark", 16, C.green)
                            TX("두 방식의 0~\(max(0, (scan?.next ?? WalletDiscovery.batch) - 1))번 통장을 확인했어요", .r, 13, Color(hex: "#D8D8DC"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(C.green.opacity(0.10)))
                        .padding(.top, 16)
                    }
                    if let other = scan?.otherScheme, let n = scan?.otherUsed, n > 0 {
                        // 고르지 않은 방식에서만 보이는 돈 — 조용히 버리지 않고 알려줌
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Icon("alert-circle", 16, C.amber)
                                TX("다른 방식에서도 쓰던 통장 \(n)개를 찾았어요", .sb, 13, C.amber)
                            }
                            TX("\(other == .alt ? "Trust Wallet·Ledger" : "Phantom·MetaMask") 방식의 통장이에요. 한 지갑은 한 방식만 가져올 수 있어서 이번에는 가져오지 않아요. 그 통장의 돈은 원래 쓰던 앱에서 확인하거나 옮겨주세요.",
                               .r, 13, Color(hex: "#D8D8DC"), lh: 19)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(C.amber.opacity(0.10)))
                        .padding(.top, 10)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(accs.enumerated()), id: \.element.id) { i, f in
                            foundRow(i, f, last: i == accs.count - 1)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.top, 14)

                    TX("잔액이나 거래 기록이 있는 통장만 가져와요. 비어 있는 통장은 나중에 '통장 추가'로 열 수 있어요. 비트코인은 통장마다 첫 받기 주소(m/84'/0'/n'/0/0) 하나, 카르다노도 첫 주소 하나만 확인해요. 다른 주소에 있는 돈은 원래 앱에서 확인해주세요.",
                       .r, 12, Color(hex: "#6B6B76"), lh: 18)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    // 빈 번호 다음에 쓴 통장이 있을 수 있음 (다른 앱에서 번호를 건너뛰고 만든 경우)
                    if let scan {
                        Tap(action: findMore) {
                            HStack(spacing: 8) {
                                if findingMore { ProgressView().tint(C.sub).scaleEffect(0.8) }
                                TX(findingMore ? "더 찾는 중이에요" : "다음 번호 \(WalletDiscovery.batch)개 더 찾기", .m, 13, C.sub)
                                    .underline(color: C.sub)
                            }
                            .padding(.vertical, 8)
                        }
                        .disabled(findingMore)
                        .padding(.top, 4)
                        .accessibilityHint("\(scan.next + 1)번째 번호부터 확인해요")
                    }

                    TX("지갑 이름", .sb, 13, C.sub).padding(.top, 22)
                    Field(text: $name, placeholder: "예: Phantom", maxLength: 16).padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            OButton("가져오기", disabled: accs.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty, loading: saving) { finish() }
        }
    }

    private func foundRow(_ i: Int, _ f: FoundAccount, last: Bool) -> some View {
        var logos: [(String?, String?)] = []
        if f.assets.isEmpty {
            for n in f.nets.prefix(3) { logos.append((nil, n)) }
        } else {
            for a in f.assets.prefix(3) { logos.append((a, nil)) }
        }
        let netText = f.nets.isEmpty ? "" : f.nets.joined(separator: "·")
        let sub: String
        if f.assets.isEmpty {
            sub = netText.isEmpty ? "비어 있어요" : "\(netText) · 거래 기록만 있어요"
        } else {
            let a = f.assets.prefix(3).map { $0 == "usdt0" ? "USDT0" : $0.uppercased() }.joined(separator: ", ")
            sub = netText.isEmpty ? a : "\(netText) · \(a)"
        }
        return HStack(spacing: 12) {
            HStack(spacing: -7) {
                if logos.isEmpty {
                    WalletMark(wallet: nil, size: 22)
                }
                ForEach(Array(logos.enumerated()), id: \.offset) { _, l in
                    CoinLogo(asset: l.0, network: l.1, size: 22, ring: C.surface)
                        .overlay(Circle().strokeBorder(C.surface, lineWidth: 2))
                }
            }
            .frame(minWidth: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                TX("통장 \(i + 1)", .sb, 16)
                TX(sub, .r, 13, C.mute, lines: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TX(wonOf(f.usd), .sb, 16, f.usd > 0 ? C.text : Color(hex: "#6B6B76"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(C.line).frame(height: 1) } }
    }

    private func findMore() {
        guard let cur = scan, !findingMore else { return }
        findingMore = true
        let w = WalletKeys.normalize(words)
        Task {
            let r = await store.discoverMore(words: w, scan: cur)
            await MainActor.run {
                let added = r.accounts.count - cur.accounts.count
                scan = r
                findingMore = false
                if added > 0 { haptic(.success) }
                toast(added > 0 ? "통장 \(added)개를 더 찾았어요" : "더 찾은 통장은 없어요", added > 0 ? "checkmark-circle" : "information-circle-outline")
            }
        }
    }

    private func finish() {
        guard let scan, !saving else { return }
        saving = true
        let w = WalletKeys.normalize(words)
        let n = name
        guard store.importWallet(words: w, name: n, scan: scan) else {
            saving = false
            toast("지갑을 저장하지 못했어요", "alert-circle")
            return
        }
        words = ""
        haptic(.success)
        router.modal = nil
        after(0.45) { toast("\(josa(n, "을/를")) 가져왔어요", "download-outline") }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
