import Foundation

// 통장 · 지갑
// 지갑 = 12단어 하나 (은행). main = 처음 만든 Ouryn 지갑, 나머지는 가져오거나 새로 만든 지갑
// 통장 = 같은 12단어의 n번째 계정 (계좌). 통장끼리는 블록체인에서 서로 다른 사람처럼 보임
// 지금 통장의 상태는 AppState 에 그대로 두고, 다른 통장은 AccountSnap 에 보관했다가 바꿀 때 맞바꿈

struct WalletBox: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var imported = false
    var scheme: KeyScheme = .standard
    var backedUp = false
    var backedUpAt: Date? = nil
    var isMain: Bool { id == "main" }
}

/// 통장마다 따로인 상태
struct AccountSnap: Codable, Equatable {
    var networkBalances: [String: [String: String]]?
    var networkSynced: [String: Date]?
    var networkErrors: [String: String]?
    var wallet: Wallet
    var coins: [String: Double]
    var lastSync: Date?
    var syncFailed: [String]
    var tx: [Tx]
    var deposits: [Deposit]
    var pendingBroadcasts: [PendingBroadcast]?
    var exRegistered: [String: Bool]
    var savings: SavingsState
    // 홈 목록 — 통장마다 따로 (예전 통장은 nil → 묶어서 보기 · 기본 순서)
    var homeMode: String? = nil
    var assetOrder: [String]? = nil
}

extension AccountSnap {
    static let empty = AccountSnap(networkBalances: nil, networkSynced: nil, networkErrors: nil,
                                   wallet: Wallet(circle: 0, tether: 0), coins: [:], lastSync: nil, syncFailed: [],
                                   tx: [], deposits: [], pendingBroadcasts: nil, exRegistered: [:],
                                   savings: SavingsState(principal: 0, earned: 0, apy: 0))

    init(_ s: AppState) {
        self.init(networkBalances: s.networkBalances, networkSynced: s.networkSynced, networkErrors: s.networkErrors,
                  wallet: s.wallet, coins: s.coins, lastSync: s.lastSync, syncFailed: s.syncFailed, tx: s.tx,
                  deposits: s.deposits, pendingBroadcasts: s.pendingBroadcasts, exRegistered: s.exRegistered,
                  savings: s.savings, homeMode: s.homeMode, assetOrder: s.assetOrder)
    }

    func apply(to s: inout AppState) {
        s.networkBalances = networkBalances; s.networkSynced = networkSynced; s.networkErrors = networkErrors
        s.wallet = wallet; s.coins = coins; s.lastSync = lastSync; s.syncFailed = syncFailed
        s.tx = tx; s.deposits = deposits; s.pendingBroadcasts = pendingBroadcasts
        s.exRegistered = exRegistered; s.savings = savings
        s.homeMode = homeMode ?? "group"
        var order = assetOrder ?? ASSET_IDS
        for id in ASSET_IDS where !order.contains(id) { order.append(id) }
        s.assetOrder = order
    }
}

struct Account: Codable, Equatable, Identifiable {
    var id: String          // "<지갑 id>#<번호>"
    var walletId: String
    var index: Int
    var name: String
    var addrs: ChainAddrs
    var snap: AccountSnap? = nil
    var test: Bool? = nil   // 테스트 통장 (테스트넷)
    var isTest: Bool { test == true }
}

/// 주소가 내 통장 것일 때 — 통장 이름("생활비 통장")과 지금 보고 있는 통장인지
struct OwnAccount: Equatable {
    let id: String
    let title: String
    let active: Bool
}

// MARK: - 파생 값

extension AppState {
    var walletList: [WalletBox] { wallets ?? [] }
    var accountList: [Account] { accounts ?? [] }
    var activeId: String { activeAccount ?? "main#0" }
    var currentAccount: Account? { accountList.first { $0.id == activeId } }
    var currentWallet: WalletBox? { walletList.first { $0.id == (currentAccount?.walletId ?? "main") } }
    var accountName: String { currentAccount?.name ?? "기본" }
    /// 홈 위 "생활비 통장"
    var accountTitle: String { accountName.contains("통장") ? accountName : accountName + " 통장" }

    /// 그 지갑의 통장 (진짜 통장 먼저, 테스트 통장은 뒤에)
    func accountsIn(_ wallet: String) -> [Account] {
        let mine = accountList.filter { $0.walletId == wallet }
        let real = mine.filter { !$0.isTest }.sorted { $0.index < $1.index }
        let test = mine.filter { $0.isTest }.sorted { $0.index < $1.index }
        return real + test
    }
    var realAccounts: [Account] { accountList.filter { !$0.isTest } }
    var testAccount: Account? { accountList.first { $0.isTest } }
    var inTest: Bool { currentAccount?.isTest ?? false }
    func walletBackedUp(_ id: String) -> Bool {
        id == currentWallet?.id ? backedUp : (walletList.first { $0.id == id }?.backedUp ?? false)
    }

    /// 그 통장의 상태로 바꿔본 사본 (지금 시세 그대로)
    func view(of a: Account) -> AppState {
        if a.id == activeId { return self }
        var s = self
        (a.snap ?? .empty).apply(to: &s)
        return s
    }
    func totalUsd(_ a: Account) -> Double { a.id == activeId ? grandTotal : view(of: a).grandTotal }
    /// 진짜 통장 합계 (테스트 통장은 가치가 없어서 뺌)
    var allAccountsUsd: Double { realAccounts.reduce(0) { $0 + totalUsd($1) } }

    /// 잔액이 있는 자산 (많은 순)
    func held(_ a: Account) -> [String] {
        let s = view(of: a)
        let ids = ["usdt", "usdc"] + COIN_IDS
        return ids.filter { s.balance($0) > 0 }
            .sorted { s.balance($0) * s.usdPrice($0) > s.balance($1) * s.usdPrice($1) }
    }
    /// 이 주소가 내 통장 주소인지 — 저장해 둔 공개 주소끼리만 비교 (12단어는 꺼내지 않음)
    /// 이더리움·맨틀·Avalanche 는 같은 0x 주소를 함께 쓰고, 대소문자는 무시
    /// 지금 통장 > 같은 종류(진짜/테스트) 통장 > 나머지 순으로 찾음
    func ownAccount(address raw: String, net: String) -> OwnAccount? {
        let a = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, let network = WalletNetwork(rawValue: net) else { return nil }
        func pick(_ x: ChainAddrs) -> String? {
            switch network {
            case .solana: return x.solana
            case .ethereum, .mantle, .avalanche: return x.ethereum
            case .tron: return x.tron
            case .bitcoin: return x.bitcoin
            case .cardano: return x.cardano
            }
        }
        func same(_ b: String?) -> Bool {
            guard let b, !b.isEmpty else { return false }
            return network.isEVM ? b.lowercased() == a.lowercased() : b == a
        }
        if let mine = addrs, same(pick(mine)) { return OwnAccount(id: activeId, title: accountTitle, active: true) }
        let test = inTest
        let others = accountList.filter { $0.id != activeId }
            .sorted { ($0.isTest == test ? 0 : 1) < ($1.isTest == test ? 0 : 1) }
        guard let hit = others.first(where: { same(pick($0.addrs)) }) else { return nil }
        return OwnAccount(id: hit.id, title: hit.name.contains("통장") ? hit.name : hit.name + " 통장", active: false)
    }

    func heldLabel(_ a: Account) -> String {
        let h = held(a).map { $0 == "usdt0" ? "USDT0" : $0.uppercased() }
        if h.isEmpty { return "아직 비어 있어요" }
        return h.count > 2 ? h.prefix(2).joined(separator: " · ") + " 외 \(h.count - 2)개" : h.joined(separator: " · ")
    }
}

// MARK: - 통장 바꾸기 · 더하기

extension Store {
    func slot(of a: Account) -> KeySlot {
        KeySlot(wallet: a.walletId, index: a.index,
                scheme: st.walletList.first { $0.id == a.walletId }?.scheme ?? .standard, test: a.isTest)
    }

    /// 서명·12단어 보기가 지금 통장을 따르게
    func applySlot() {
        let s = st.currentAccount.map { slot(of: $0) } ?? KeySlot()
        WalletKeys.active = s
        Testnet.on = s.test
    }

    /// 예전 상태 → 지갑 1개(Ouryn 지갑) · 통장 1개(기본)
    func migrateAccounts(main: ChainAddrs) {
        guard st.accounts?.isEmpty ?? true else { return }
        update { s in
            s.wallets = [WalletBox(id: "main", name: "Ouryn 지갑", backedUp: s.backedUp, backedUpAt: s.backedUp ? Date() : nil)]
            s.accounts = [Account(id: "main#0", walletId: "main", index: 0, name: "기본", addrs: main)]
            s.activeAccount = "main#0"
        }
    }

    /// 앱을 켤 때: Keychain 의 12단어로 주소를 다시 계산해 맞춤
    func restoreAccounts(main: ChainAddrs) {
        migrateAccounts(main: main)
        update { s in
            if let i = s.accounts?.firstIndex(where: { $0.id == "main#0" }) { s.accounts?[i].addrs = main }
        }
        if st.activeId == "main#0" {
            if st.addrs != main { update { $0.addrs = main } }
        } else if let acc = st.currentAccount, let a = WalletKeys.addrs(slot: slot(of: acc)) {
            update { s in
                s.addrs = a
                if let i = s.accounts?.firstIndex(where: { $0.id == acc.id }) { s.accounts?[i].addrs = a }
            }
        } else {
            // 지갑의 12단어를 못 찾음 → 기본 통장으로
            update { s in
                let main0 = s.accounts?.first { $0.id == "main#0" }
                (main0?.snap ?? .empty).apply(to: &s)
                s.addrs = main
                s.activeAccount = "main#0"
                s.backedUp = s.walletList.first { $0.isMain }?.backedUp ?? s.backedUp
            }
        }
        applySlot()
    }

    /// 앱을 켤 때 (Face ID 보호 항목): 12단어를 읽지 않고 저장해 둔 주소로. 지금 통장의 지갑 항목이 없어졌으면 기본 통장으로
    func restoreAccountsFromCache() {
        if let acc = st.currentAccount, acc.walletId != "main", !WalletKeys.exists(wallet: acc.walletId),
           let main = st.accountList.first(where: { $0.id == "main#0" }) {
            update { s in
                (main.snap ?? .empty).apply(to: &s)
                s.addrs = main.addrs
                s.activeAccount = "main#0"
                s.backedUp = s.walletList.first { $0.isMain }?.backedUp ?? s.backedUp
            }
        }
        applySlot()
    }

    func switchAccount(_ id: String) {
        guard id != st.activeId, let target = st.accountList.first(where: { $0.id == id }) else { return }
        update { s in
            let from = s.activeId
            // 상태 전체를 먼저 복사해두고 넣음 (s 를 읽으면서 s.accounts 를 고치면 동시 접근 오류)
            let snap = AccountSnap(s), backed = s.backedUp
            if let i = s.accounts?.firstIndex(where: { $0.id == from }) { s.accounts?[i].snap = snap }
            if let w = s.currentWallet?.id, let j = s.wallets?.firstIndex(where: { $0.id == w }) { s.wallets?[j].backedUp = backed }
            (target.snap ?? .empty).apply(to: &s)
            s.addrs = target.addrs
            s.activeAccount = target.id
            if let k = s.accounts?.firstIndex(where: { $0.id == target.id }) { s.accounts?[k].snap = nil }
            s.backedUp = s.walletList.first { $0.id == target.walletId }?.backedUp ?? false
            s.notifications.removeAll { $0.action == "recovery" }
            if !s.backedUp {
                s.notifications.insert(Noti(id: "backup-reminder", icon: "key", title: "복구 문구를 적어주세요",
                                            body: "돈을 넣기 전에 종이에 적어두세요", ts: Date(), read: true, action: "recovery"), at: 0)
            }
        }
        applySlot()
        haptic(.select)
        Task { await sync() }
    }

    /// 같은 12단어의 다음 번호로 통장 하나 더 (새로 적을 것 없음). test = 테스트넷에서 쓰는 테스트 통장
    /// 다음 번호의 주소를 계산하려면 12단어가 필요 → Face ID 한 번
    @MainActor @discardableResult
    func addAccount(walletId: String, test: Bool = false) async -> Account? {
        // 테스트넷 주소 계산 자체 검사를 통과해야 테스트 통장을 만듦
        if test && !WalletKeys.passed("테스트넷") { return nil }
        let mine = st.accountsIn(walletId)
        // 번호는 진짜·테스트 통장이 함께 씀 → 주소가 서로 겹치지 않음
        // 지운 통장의 번호부터 다시 씀 → 지웠던 통장을 다시 추가하면 같은 주소·잔액이 돌아옴
        let used = Set(mine.map(\.index))
        let next = (0...).first { !used.contains($0) } ?? 0
        let scheme = st.walletList.first { $0.id == walletId }?.scheme ?? .standard
        guard let a = await WalletKeys.addrs(slot: KeySlot(wallet: walletId, index: next, scheme: scheme, test: test),
                                             reason: test ? "테스트 통장 만들기" : "새 통장 만들기") else { return nil }
        // Face ID 를 기다리는 사이 같은 번호가 생겼으면 그만둠
        guard !st.accountsIn(walletId).contains(where: { $0.index == next }) else { return nil }
        let tests = mine.filter(\.isTest).count, reals = mine.count - tests
        let name = test ? (tests == 0 ? "테스트 통장" : "테스트 통장 \(tests + 1)") : "통장 \(reals + 1)"
        let acc = Account(id: "\(walletId)#\(next)", walletId: walletId, index: next, name: name, addrs: a, snap: .empty, test: test ? true : nil)
        update { $0.accounts = ($0.accounts ?? []) + [acc] }
        return acc
    }

    // MARK: 테스트 통장

    /// 테스트 통장으로 바꾸기 — 지금 지갑의 테스트 통장 → 아무 테스트 통장 → 없으면 지금 지갑에 하나 만듦
    func openTestAccount() {
        guard !st.inTest else { return }
        let w = st.currentWallet?.id ?? "main"
        if let t = st.accountsIn(w).first(where: \.isTest) ?? st.testAccount { switchAccount(t.id); return }
        Task { @MainActor in
            guard let acc = await addAccount(walletId: w, test: true) else { toast("테스트 통장을 만들지 못했어요", "alert-circle"); return }
            switchAccount(acc.id)
        }
    }

    /// 테스트 통장에서 진짜 통장으로 (같은 지갑의 첫 통장)
    func leaveTestAccount() {
        guard st.inTest else { return }
        let w = st.currentWallet?.id ?? "main"
        switchAccount(st.accountsIn(w).first(where: { !$0.isTest })?.id ?? "main#0")
    }

    /// 테스트 통장 지우기 (12단어는 그대로 · 언제든 다시 만들 수 있음)
    func removeTestAccount(_ id: String) { removeAccount(id) }

    /// 지갑의 마지막 진짜 통장이 아니면 지울 수 있음
    func canRemove(_ a: Account) -> Bool {
        a.isTest || st.accountsIn(a.walletId).filter { !$0.isTest }.count > 1
    }

    /// 통장 지우기 — 목록에서만 빼는 것. 12단어와 블록체인의 돈은 그대로라 같은 번호를 다시 추가하면 돌아옴
    func removeAccount(_ id: String) {
        guard let a = st.accountList.first(where: { $0.id == id }), canRemove(a) else { return }
        if st.activeId == a.id {
            let next = st.accountsIn(a.walletId).first { $0.id != a.id && !$0.isTest }?.id ?? "main#0"
            switchAccount(next)
        }
        update { $0.accounts?.removeAll { $0.id == a.id } }
    }

    // MARK: 지갑 지우기

    /// Ouryn 지갑이 아닌 지갑을 이 폰에서 지움 → 기본 통장으로
    /// Keychain 에서 지운 게 확인될 때만 목록에서 뺌. 실패하면 false (지갑은 그대로)
    @discardableResult
    func deleteWallet(_ id: String) -> Bool {
        guard id != "main", st.walletList.contains(where: { $0.id == id }) else { return false }
        guard WalletKeys.deleteWallet(id) else { return false }
        if st.currentWallet?.id == id { switchAccount("main#0") }
        update { s in
            s.accounts?.removeAll { $0.walletId == id }
            s.wallets?.removeAll { $0.id == id }
        }
        return true
    }

    func renameAccount(_ id: String, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        update { s in if let i = s.accounts?.firstIndex(where: { $0.id == id }) { s.accounts?[i].name = String(n.prefix(12)) } }
    }

    func renameWallet(_ id: String, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        update { s in if let i = s.wallets?.firstIndex(where: { $0.id == id }) { s.wallets?[i].name = String(n.prefix(16)) } }
    }

    // MARK: 지갑 더하기

    private func walletId() -> String { "w\(Int(Date().timeIntervalSince1970 * 1000))" }

    /// 입력한 12단어가 지금 통장의 지갑인지 — 저장해 둔 주소와 비교
    /// (Keychain 을 읽지 않아서 Face ID 가 고장 났거나 항목이 없어져도 확인 가능)
    func wordsMatchCurrent(_ words: String) -> Bool {
        let acc = st.currentAccount
        guard let cached = acc?.addrs ?? st.addrs,
              let a = WalletKeys.addrs(words: words, slot: acc.map { slot(of: $0) } ?? KeySlot()) else { return false }
        return a.solana == cached.solana && a.ethereum == cached.ethereum && a.bitcoin == cached.bitcoin
    }

    /// 이 폰에 있는 지갑 중 하나의 12단어인지 (비밀번호를 잊었을 때)
    func wordsMatchAnyWallet(_ words: String) -> Bool {
        Set(["main"] + st.walletList.map(\.id)).contains { WalletKeys.holds(words, wallet: $0) } || wordsMatchCurrent(words)
    }

    /// 이미 이 폰에 있는 지갑이면 그 이름
    func existingWallet(words: String) -> String? {
        st.walletList.first { WalletKeys.holds(words, wallet: $0.id) }?.name
    }

    /// 새 12단어 만들기 → 그 지갑의 첫 통장으로 바꿈. 백업은 복구 문구 화면에서
    @discardableResult
    func createWallet() -> Bool {
        let id = walletId()
        guard let a = WalletKeys.createExtra(id: id) else { return false }
        let count = st.walletList.filter { !$0.imported && !$0.isMain }.count
        let box = WalletBox(id: id, name: count == 0 ? "새 지갑" : "새 지갑 \(count + 1)")
        let acc = Account(id: id + "#0", walletId: id, index: 0, name: "통장 1", addrs: a, snap: .empty)
        update { s in
            s.wallets = (s.wallets ?? []) + [box]
            s.accounts = (s.accounts ?? []) + [acc]
        }
        switchAccount(acc.id)
        return true
    }

    /// 찾은 통장들로 지갑 가져오기
    @discardableResult
    func importWallet(words: String, name: String, scan: WalletScan) -> Bool {
        let id = walletId()
        guard !scan.accounts.isEmpty, WalletKeys.saveExtra(words: words, id: id) else { return false }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let box = WalletBox(id: id, name: n.isEmpty ? "가져온 지갑" : String(n.prefix(16)), imported: true, scheme: scan.scheme)
        let accs = scan.accounts.enumerated().map { i, f in
            Account(id: "\(id)#\(f.index)", walletId: id, index: f.index, name: "통장 \(i + 1)", addrs: f.addrs, snap: f.snap)
        }
        update { s in
            s.wallets = (s.wallets ?? []) + [box]
            s.accounts = (s.accounts ?? []) + accs
        }
        switchAccount(accs[0].id)
        return true
    }

    /// 12단어로 쓰던 통장 찾기 — Phantom·MetaMask 방식(standard)과 Trust·Ledger 방식(alt)을 다 확인
    func discover(words: String) async -> WalletScan {
        // 찾기는 메인넷에서
        if Testnet.on { await MainActor.run { self.switchAccount("main#0") } }
        let base = await MainActor.run { self.st }
        async let a = WalletDiscovery.scan(words: words, scheme: .standard, base: base)
        async let b = WalletDiscovery.scan(words: words, scheme: .alt, base: base)
        let std = await a, alt = await b
        let altWins = alt.accounts.count > std.accounts.count
            || (alt.accounts.count == std.accounts.count && alt.usd > std.usd + 0.01)
        var pick = altWins ? alt : std
        // 한 지갑은 한 방식만 가져옴 → 다른 방식에서만 보이는 쓰던 통장이 있으면 버리지 않고 알려줌
        let other = altWins ? std : alt
        pick.otherScheme = other.scheme
        pick.otherUsed = WalletDiscovery.extraUsed(other, beyond: pick)
        if !pick.accounts.isEmpty { return pick }
        // 아무 기록도 없으면 첫 통장 하나만 (못 읽은 번호가 있었다면 그대로 알려줌)
        guard let addrs = WalletKeys.addrs(words: words, slot: KeySlot(wallet: "", index: 0, scheme: .standard)) else { return std }
        return WalletScan(scheme: .standard, accounts: [FoundAccount(index: 0, addrs: addrs, usd: 0, assets: [], nets: [], history: false, snap: .empty)],
                          unchecked: Array(Set(std.unchecked + alt.unchecked)).sorted(), next: std.next,
                          otherScheme: .alt, otherUsed: WalletDiscovery.extraUsed(alt, beyond: std))
    }

    /// '더 찾기' — 같은 방식으로 다음 번호들을 확인해서 이어 붙임
    func discoverMore(words: String, scan: WalletScan) async -> WalletScan {
        if Testnet.on { await MainActor.run { self.switchAccount("main#0") } }
        let base = await MainActor.run { self.st }
        let more = await WalletDiscovery.scan(words: words, scheme: scan.scheme, base: base, from: scan.next)
        let known = Set(scan.accounts.map(\.index))
        // 처음에 아무것도 없어서 넣어둔 빈 0번은, 더 찾아서 나온 게 있으면 빼지 않고 그대로 둠
        return WalletScan(scheme: scan.scheme,
                          accounts: scan.accounts + more.accounts.filter { !known.contains($0.index) },
                          unchecked: scan.unchecked + more.unchecked,
                          next: more.next,
                          otherScheme: scan.otherScheme, otherUsed: scan.otherUsed)
    }
}

// MARK: - 통장 찾기

struct FoundAccount: Identifiable {
    let index: Int
    let addrs: ChainAddrs
    let usd: Double
    let assets: [String]
    let nets: [String]
    let history: Bool
    let snap: AccountSnap
    var id: Int { index }
}

struct WalletScan {
    let scheme: KeyScheme
    let accounts: [FoundAccount]
    /// 조회가 실패해서 쓰던 통장인지 알 수 없는 번호
    var unchecked: [Int] = []
    /// '더 찾기'를 누르면 이 번호부터
    var next = 0
    /// 고르지 않은 다른 방식과, 그 방식에서만 보이는 쓰던 통장 수 (같은 주소는 뺌)
    var otherScheme: KeyScheme? = nil
    var otherUsed = 0
    var usd: Double { accounts.reduce(0) { $0 + $1.usd } }
}

enum WalletDiscovery {
    static let batch = 5

    /// other 방식에서 찾은 쓰던 통장 중, pick 방식의 어떤 통장과도 주소가 다른 네트워크를 쓰는 통장 수
    /// (0번 통장의 이더리움·비트코인·카르다노·트론 주소는 두 방식이 같아서 겹치는 것은 세지 않음)
    static func extraUsed(_ other: WalletScan, beyond pick: WalletScan) -> Int {
        func addr(_ a: ChainAddrs, _ net: String) -> String? {
            switch net {
            case "솔라나": return a.solana
            case "비트코인": return a.bitcoin
            case "카르다노": return a.cardano
            case "트론": return a.tron
            default: return a.ethereum.lowercased()   // 이더리움 · 맨틀 · Avalanche C-Chain
            }
        }
        return other.accounts.filter { o in
            o.nets.contains { net in
                let theirs = addr(o.addrs, net)
                return !pick.accounts.contains { addr($0.addrs, net) == theirs }
            }
        }.count
    }

    enum Probe { case used(FoundAccount), empty, unknown }

    /// from 번호부터 차례로 최대 batch 개를 봄. 잔액도 기록도 없다고 '확인된' 번호가 나오면 멈춤
    /// (BIP44 계정 찾기 규칙). 조회에 실패한 번호는 빈 통장으로 치지 않고 건너뛰며 따로 표시
    static func scan(words: String, scheme: KeyScheme, base: AppState, from: Int = 0) async -> WalletScan {
        var found: [FoundAccount] = []
        var unchecked: [Int] = []
        var i = from
        while i < from + batch {
            let slot = KeySlot(wallet: "", index: i, scheme: scheme)
            guard let a = await Task.detached(operation: { WalletKeys.addrs(words: words, slot: slot) }).value else { break }
            switch await probe(a, index: i, base: base) {
            case .used(let f): found.append(f)
            case .unknown: unchecked.append(i)
            case .empty: return WalletScan(scheme: scheme, accounts: found, unchecked: unchecked, next: i + 1)
            }
            i += 1
        }
        return WalletScan(scheme: scheme, accounts: found, unchecked: unchecked, next: i)
    }

    /// 잔액·기록이 있으면 그 통장. 다 확인했는데 없으면 empty, 어느 하나라도 못 읽었으면 unknown
    static func probe(_ a: ChainAddrs, index: Int, base: AppState) async -> Probe {
        let nets = Set(["솔라나", "이더리움", "비트코인", "카르다노"].filter { WalletKeys.passed($0) })
        async let balJob = ChainAPI.balances(a, only: nets)
        async let extraJob = MultiChainAPI.fetch(a)
        async let solJob = solanaHistory(a.solana)
        async let ethJob = ethereumHistory(a.ethereum)
        // 자체 검사를 통과하지 못한 비트코인 주소는 확인하지 않음 (빈 주소 → false)
        async let btcJob = bitcoinHistory(nets.contains("비트코인") ? a.bitcoin : "")
        let bal = await balJob, extra = await extraJob
        let solUsed = await solJob, ethUsed = await ethJob, btcUsed = await btcJob

        var s = base
        AccountSnap.empty.apply(to: &s)
        Store.mergeLegacy(&s, bal)
        Store.mergeNetworks(&s, extra, legacy: bal)
        s.lastSync = Date()
        let ids = ["usdt", "usdc"] + COIN_IDS
        let assets = ids.filter { s.balance($0) > 0 }
            .sorted { s.balance($0) * s.usdPrice($0) > s.balance($1) * s.usdPrice($1) }
        var used: [String] = []
        for (net, assetsOn) in s.networkBalances ?? [:] where assetsOn.values.contains(where: { ($0 as NSString).doubleValue > 0 }) {
            used.append(net)
        }
        if solUsed == true && !used.contains("솔라나") { used.append("솔라나") }
        if ethUsed == true && !used.contains("이더리움") { used.append("이더리움") }
        if btcUsed == true && !used.contains("비트코인") { used.append("비트코인") }
        if !assets.isEmpty || !used.isEmpty {
            return .used(FoundAccount(index: index, addrs: a, usd: s.grandTotal, assets: assets, nets: used.sorted(),
                                      history: solUsed == true || ethUsed == true || btcUsed == true, snap: AccountSnap(s)))
        }
        // 아무것도 못 찾았어도, 못 읽은 곳이 있으면 '비었다'고 단정하지 않음
        let balanceFailed = !Set(bal.failed).isDisjoint(with: nets)
            || extra.contains { $0.error != nil && WalletKeys.passed($0.network.rawValue) }
        let historyFailed = solUsed == nil || ethUsed == nil || btcUsed == nil
        return balanceFailed || historyFailed ? .unknown : .empty
    }

    /// 기록이 있으면 true, 없으면 false, 못 읽었으면 nil
    private static func solanaHistory(_ addr: String) async -> Bool? {
        guard !addr.isEmpty else { return false }
        var r = URLRequest(url: ChainAPI.solanaRPC); r.httpMethod = "POST"; r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "getSignaturesForAddress", "params": [addr, ["limit": 1]],
        ])
        guard let res = try? await URLSession.shared.data(for: r),
              let json = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any],
              let list = json["result"] as? [Any] else { return nil }
        return !list.isEmpty
    }

    private static func ethereumHistory(_ addr: String) async -> Bool? {
        guard !addr.isEmpty else { return false }
        guard let n = try? await MultiChainAPI.rpc(.ethereum, "eth_getTransactionCount", [addr, "latest"]) else { return nil }
        return UInt64(n.dropFirst(2), radix: 16).map { $0 > 0 }
    }

    /// 비트코인: 받은 적만 있고 지금 0인 주소도 '쓰던 통장'
    private static func bitcoinHistory(_ addr: String) async -> Bool? {
        guard !addr.isEmpty else { return false }
        guard let data = try? await BitcoinTransfer.get("/address/" + addr),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let chain = (json["chain_stats"] as? [String: Any])?["tx_count"] as? Int
        let pool = (json["mempool_stats"] as? [String: Any])?["tx_count"] as? Int
        guard let chain else { return nil }
        return chain + (pool ?? 0) > 0
    }
}
