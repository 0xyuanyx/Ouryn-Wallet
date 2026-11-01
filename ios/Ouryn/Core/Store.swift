import SwiftUI
import Combine

// 앱 상태 + 저장소
// 실제 지갑: 키는 WalletKeys(Keychain), 잔액·시세는 ChainAPI 로 메인넷에서 읽음 (읽기 전용)
// 이 파일에 남은 '가짜'는 근처 사람 찾기(NEARBY)와 카메라 없는 기기용 체험 QR(SCAN_DEMO) 뿐

// 근처에 있는 사람 (목업 — 보내기가 열릴 때 실제 기능으로 바꿀 자리)
struct NearbyPerson { let addr: String; let device: String }
let NEARBY: [NearbyPerson] = [
    NearbyPerson(addr: "9aF3xQ1mZ8pLkT2vW7rYc4NbD6sHgJ5eU0oRiP3tKdMn", device: "민지의 아이폰"),
    NearbyPerson(addr: "Jn5pW2kR8mQ1tX7vZ4cY9bL3hG6fD0sA2eUoIi8rTyWq", device: "준호의 갤럭시"),
]
/// 카메라가 없을 때(시뮬레이터 등) '체험용 QR 인식하기'가 돌려주는 요청
let SCAN_DEMO = PayRequest(to: "Jn5pW2kR8mQ1tX7vZ4cY9bL3hG6fD0sA2eUoIi8rTyWq", usd: 12, asset: "usdc")

/// 이전 송금 화면·이자·자동 송금은 계속 잠금. 새 TransferFlow는 별도 실제 송금 경로.
let LIVE_SEND = false

let COIN_IDS = ["sol", "eth", "btc", "ada", "night", "trx", "mnt", "avax", "usdt0"]
let DOLLAR_NET = "솔라나"

// MARK: - 데이터

enum TxType: String, Codable { case receive, send, interest, save, unsave }

/// done: 완료 · pending: 오는 중/확인 중 · delayed: 평소보다 늦음 · failed: 실패
enum TxStatus: String, Codable { case done, pending, delayed, failed }

struct Tx: Codable, Identifiable, Equatable {
    var id: String
    var hash: String
    var type: TxType
    var addr: String?
    var amt: Double          // 달러 환산 (원화 표시는 amt × RATE)
    var memo: String
    var ts: Date
    var asset: String? = nil // usdc · usdt · sol · eth · btc · ada · night
    var qty: Double? = nil   // 자산 수량
    var net: String? = nil   // 네트워크 이름
    var status: TxStatus = .done
    var feeUpper: String? = nil
    var via: String? = nil   // 보낸 곳 이름 (예: 업비트) — 주소를 모를 때
}

extension Tx {
    var assetId: String { asset ?? "usdc" }
    var isDollar: Bool { assetId == "usdc" || assetId == "usdt" }
    var quantity: Double { qty ?? amt }
    var network: String { net ?? ASSET_NET[assetId] ?? DOLLAR_NET }
    var inFlight: Bool { status == .pending || status == .delayed }
}

struct Noti: Codable, Identifiable, Equatable {
    var id: String
    var icon: String
    var title: String
    var body: String
    var ts: Date
    var read: Bool
    var action: String? = nil
    var test: Bool? = nil   // 테스트 통장에서 생긴 알림 (진짜 통장 알림함과 섞지 않음)
    var acct: String? = nil // 어느 통장에서 생긴 알림인지 (통장 id)
}

extension Noti {
    /// 통장 id — 예전 알림은 이동 정보("asset:sol|main#1")에서 읽음
    var accountId: String? {
        if let acct { return acct }
        guard let a = action, a.contains("|") else { return nil }
        return a.split(separator: "|").last.map(String.init)
    }
}

struct Schedule: Codable, Identifiable, Equatable {
    var id: String
    var to: String
    var amt: Double
    var day: Int
    var memo: String
}

/// 거래소에서 오는 돈 기다리기 — 실제 잔액이 늘어나는지 지켜봄
struct Deposit: Codable, Identifiable, Equatable {
    var id: String        // 같은 id 의 Tx 와 짝
    var asset: String
    var exchange: String
    var net: String
    var start: Date
    var baseline: Double  // 시작할 때 잔액
}

enum DepositTiming {
    static let checkEvery: Double = 15      // 기다리는 동안 잔액 확인 간격 (초)
    static let networkPhase: Double = 30    // 이만큼 지나면 '네트워크 확인 중' 단계로 표시
    static let slowAfter: Double = 30 * 60  // 30분 넘으면 '늦어지는 중'
}

struct Contact: Codable, Equatable { var name: String }
struct Wallet: Codable, Equatable { var circle: Double; var tether: Double }
struct SavingsState: Codable, Equatable { var principal: Double; var earned: Double; var apy: Double }
struct CardState: Codable, Equatable { var status: String; var queue: Int? }

struct AppState: Codable, Equatable {
    var onboarded = false
    var addrs: ChainAddrs? = nil   // 실제 지갑 주소 (키는 Keychain)
    var networkBalances: [String: [String: String]]? = nil
    var networkSynced: [String: Date]? = nil
    var networkErrors: [String: String]? = nil
    var backedUp = false           // 복구 문구를 적어뒀는지
    var pin: String? = nil         // 예전 버전 호환용. 지금은 PinVault(Keychain)에 해시로 저장하고 여기는 비워 둠
    var lockEnabled = true
    var pinOnSend = true
    var bio = false
    var hide = false
    var unit = "krw"
    var wallet = Wallet(circle: 0, tether: 0)
    var coins: [String: Double] = [:]
    var prices: [String: Double] = [:]  // 1개당 원화 (CoinGecko)
    var change: [String: Double] = [:]  // 24시간 등락률 %
    var usdKrw: Double = 1390           // 테더 원화 시세 = 1달러
    var lastSync: Date? = nil
    var syncFailed: [String] = []       // 마지막 동기화에서 못 읽은 네트워크
    var exRegistered: [String: Bool] = [:]
    var homeMode = "group"
    var assetOrder = ASSET_IDS
    var savings = SavingsState(principal: 0, earned: 0, apy: 0)
    var contacts: [String: Contact] = [:]
    var savedRecipients: [SavedRecipient]? = nil
    var pendingBroadcasts: [PendingBroadcast]? = nil
    var tx: [Tx] = []
    var deposits: [Deposit] = []
    var card = CardState(status: "none", queue: nil)
    var schedules: [Schedule] = []
    var notify: [String: Bool] = ["receive": true, "interest": true, "price": true, "krw": false, "jpy": false]
    var notifications: [Noti] = []
    var wallets: [WalletBox]? = nil      // 지갑 = 12단어 하나 (main = Ouryn 지갑)
    var accounts: [Account]? = nil       // 통장 = 지갑 안의 번호 (지금 통장이 아닌 것만 snap 에 상태 보관)
    var activeAccount: String? = nil
}

// MARK: - 파생 값

extension AppState {
    var walletTotal: Double { wallet.circle + wallet.tether }
    func coinKrw(_ id: String) -> Double { (coins[id] ?? 0) * (prices[id] ?? 0) }
    var coinsUsd: Double { COIN_IDS.reduce(0) { $0 + coinKrw($1) } / RATE }
    func coinTodayKrw(_ id: String) -> Double { coinKrw(id) - coinKrw(id) / (1 + (change[id] ?? 0) / 100) }
    var dailyInterest: Double { savings.principal * savings.apy / 100 / 365 }
    var todayKrw: Double { COIN_IDS.reduce(0) { $0 + coinTodayKrw($1) } + dailyInterest * RATE }
    var grandTotal: Double { walletTotal + savings.principal + coinsUsd }
    /// 돈도 내역도 없는 첫 상태 — 원화 환산이 아니라 개수로 판단 (시세를 못 받아도 코인이 있으면 빈 지갑 아님)
    var isEmptyWallet: Bool { !hasBalance && tx.isEmpty }
    /// 어느 네트워크든 뭐라도 있는지 (달러·코인·네트워크별 원장)
    var hasBalance: Bool {
        if walletTotal > 0 || savings.principal > 0 || coins.values.contains(where: { $0 > 0 }) { return true }
        for perNet in (networkBalances ?? [:]).values {
            for raw in perNet.values where (Decimal(string: raw) ?? 0) > 0 { return true }
        }
        return false
    }
    func nameOf(_ addr: String?, net:String? = nil) -> String? {
        guard let a = addr else { return nil }
        if let net, let network = WalletNetwork(rawValue:net) {
            let id = SavedRecipient(network:network.rawValue,address:a,name:"").id
            if let recipient = savedRecipients?.first(where:{ $0.id == id }) { return recipient.name }
        }
        if let name = contacts[a]?.name { return name }
        // 사용자가 붙인 이름이 없으면, 내 통장 주소일 때 통장 이름
        if let net, let own = ownAccount(address: a, net: net) { return own.title }
        return nil
    }
    /// 지금 보이는 알림함 — 진짜 통장끼리는 하나로 모아 보고, 테스트 통장 알림은 테스트 통장에서만
    var visibleNotifications: [Noti] { notifications.filter { ($0.test == true) == inTest } }
    var unread: Int { visibleNotifications.filter { !$0.read }.count }
    var inFlight: [Tx] { tx.filter { $0.inFlight } }
    /// 솔라나 주소 (달러 받는 주소)
    var myAddr: String { address(net: DOLLAR_NET) ?? "" }
    /// 네트워크별 내 주소. 자체 검사를 통과하지 못한 체인은 nil → 화면에서 주소를 보여주지 않음
    func address(net: String) -> String? {
        guard let a = addrs, WalletKeys.passed(net) else { return nil }
        let v: String
        switch net {
        case "솔라나": v = a.solana
        case "이더리움", "맨틀", "Avalanche C-Chain": v = a.ethereum
        case "트론": v = a.tron ?? ""
        case "비트코인": v = a.bitcoin
        case "카르다노": v = a.cardano
        default: return nil
        }
        return v.isEmpty ? nil : v
    }
    /// 자산 잔액 (수량)
    func balance(_ asset: String) -> Double {
        switch asset {
        case "usdc": return wallet.circle
        case "usdt": return wallet.tether
        default: return coins[asset] ?? 0
        }
    }
    func balance(_ asset: String, net: String) -> Double? {
        guard let raw = networkBalances?[net]?[asset], let network = WalletNetwork(rawValue: net) else { return nil }
        return NSDecimalNumber(decimal: ExactAmount.display(raw: raw, decimals: network.decimals(asset))).doubleValue
    }
    /// 1개당 달러
    func usdPrice(_ asset: String) -> Double {
        if asset == "usdc" || asset == "usdt" || asset == "usdt0" { return 1 }
        return (prices[asset] ?? 0) / RATE
    }
}

// 다음 자동 보내기 날짜
func nextRun(_ day: Int) -> Date {
    let cal = Calendar.current
    let now = Date()
    var c = cal.dateComponents([.year, .month], from: now)
    c.day = day; c.hour = 9; c.minute = 0
    var d = cal.date(from: c) ?? now
    if d <= now {
        c.month = (c.month ?? 1) + 1
        d = cal.date(from: c) ?? now
    }
    return d
}
func daysUntil(_ d: Date) -> Int { Int(ceil(d.timeIntervalSinceNow / 86400)) }

// MARK: - 어떤 달러로 보내는지

struct SendPart: Equatable { let asset: String; let amt: Double }

/// 원하는 달러(prefer)가 충분하면 그것만, 아니면 서클 → 테더 순서로 나눠서
func sendPlan(_ w: Wallet, _ amt: Double, prefer: String? = nil) -> [SendPart] {
    let bal = ["usdc": w.circle, "usdt": w.tether]
    let first = prefer == "usdt" ? "usdt" : "usdc"
    let second = first == "usdc" ? "usdt" : "usdc"
    if (bal[first] ?? 0) + 1e-9 >= amt { return [SendPart(asset: first, amt: amt)] }
    if prefer == nil, (bal[second] ?? 0) + 1e-9 >= amt, (bal[first] ?? 0) <= 0 { return [SendPart(asset: second, amt: amt)] }
    let a = min(bal[first] ?? 0, amt)
    var out: [SendPart] = []
    if a > 0 { out.append(SendPart(asset: first, amt: a)) }
    out.append(SendPart(asset: second, amt: ((amt - a) * 1e6).rounded() / 1e6))
    return out
}

// MARK: - 저장소

final class Store: ObservableObject {
    static let key = "ouryn-wallet-v4" // 목업 데이터(v3)와 섞이지 않게 새 키

    @Published var st: AppState { didSet { save() } }
    @Published var locked: Bool
    @Published var unlocking = false
    @Published var syncing = false
    @Published private(set) var startupReady = false
    @Published private(set) var startupError: String?
    private(set) var hasSavedKey = false
    private var preparing = false

    private var awayAt: Date?
    private var ticker: AnyCancellable?
    private var lastPriceAt = Date.distantPast

    init() {
        var s = AppState()
        if let data = UserDefaults.standard.data(forKey: Store.key),
           let saved = try? JSONDecoder().decode(AppState.self, from: data) {
            s = saved
        }
        for asset in ASSET_IDS where !s.assetOrder.contains(asset) { s.assetOrder.append(asset) }
        if s.networkBalances == nil {
            s.networkBalances = ["솔라나":["usdc":String(format:"%.0f",s.wallet.circle * 1e6),"usdt":String(format:"%.0f",s.wallet.tether * 1e6)]]
        }
        if s.onboarded {
            s.notifications.removeAll { $0.id == "n0" && $0.title == "지갑을 만들었어요" }
            if !s.backedUp && !s.notifications.contains(where: { $0.action == "recovery" }) {
                s.notifications.insert(Noti(id: "backup-reminder", icon: "key", title: "복구 문구를 적어주세요",
                                            body: "돈을 넣기 전에 종이에 적어두세요", ts: Date(), read: true, action: "recovery"), at: 0)
            }
        }
        RATE = s.usdKrw
        st = s
        locked = s.onboarded && s.lockEnabled && (s.pin != nil || PinVault.exists)
        ticker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    @MainActor
    func prepare() async {
        guard !startupReady, !preparing else { return }
        preparing = true
        startupError = nil
        defer { preparing = false }
        let walletIds = st.walletList.map(\.id)
        let status = await Task.detached(priority: .userInitiated) {
            // 다시 저장하던 중 앱이 꺼졌으면 임시 사본으로 먼저 되살림
            WalletKeys.recoverStaged(wallets: walletIds)
            let status = WalletKeys.savedKeyStatus()
            if status != .unavailable { _ = WalletKeys.selfTest }
            return status
        }.value
        guard status != .unavailable else {
            startupError = "지갑의 보안 저장소를 열지 못했어요. 폰 잠금을 해제한 뒤 다시 시도해주세요."
            return
        }
        hasSavedKey = status == .available
        if st.onboarded && !hasSavedKey { st = AppState() }
        // 지갑 열쇠가 없으면 남아 있는 비밀번호도 의미가 없음
        if !hasSavedKey { PinVault.delete() }
        // 예전 버전: UserDefaults 의 비밀번호 → Keychain 해시로 옮김
        if let legacy = st.pin, PinVault.set(legacy) { update { $0.pin = nil } }
        if st.onboarded && hasSavedKey {
            if WalletKeys.isBiometric("main") {
                // Face ID 로 보호된 뒤로는 켤 때마다 12단어를 읽지 않음 → 저장해 둔 주소 그대로
                restoreAccountsFromCache()
            } else {
                // 예전 항목(업데이트 직후): 조용히 읽어서 주소를 한 번 맞춘 뒤 아래에서 Face ID 보호로 옮김
                let addresses = await Task.detached { WalletKeys.openExisting() }.value
                if let addresses { restoreAccounts(main: addresses) } else { restoreAccountsFromCache() }
            }
            let ids = st.walletList.map(\.id)
            await Task.detached(priority: .userInitiated) { WalletKeys.migrateProtection(wallets: ids) }.value
        }
        locked = st.onboarded && st.lockEnabled && hasPin
        startupReady = true
        Task { await sync() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(st) {
            UserDefaults.standard.set(data, forKey: Store.key)
        }
    }

    // MARK: 간편 비밀번호

    var hasPin: Bool { st.pin != nil || PinVault.exists }

    /// 모든 비밀번호 화면이 이걸로 확인 (틀린 횟수·대기 시간 포함)
    /// 맞으면 = 본인 확인 → 바뀐 Face ID 등록도 받아들임 (단, 10번 넘게 틀린 뒤라면 12단어로 풀 때까지 받아들이지 않음)
    func checkPin(_ p: String) -> PinCheck {
        if PinVault.exists {
            let r = PinVault.check(p)
            if r == .ok && !PinVault.hardLocked { Biometry.accept() }
            return PinCheck(r)
        }
        if let legacy = st.pin {   // Keychain 으로 못 옮긴 예전 비밀번호
            guard p == legacy else { return .wrong }
            if PinVault.set(p) { update { $0.pin = nil } }
            return .ok
        }
        return PinCheck(.missing)
    }

    /// 새 비밀번호 저장. Keychain 저장이 실패하면 false (비밀번호를 앱 데이터에 평문으로 남기지 않음)
    /// 본인 확인을 마친 흐름에서만 부름 → 틀린 횟수·hardLocked 초기화, 지금 Face ID 등록을 기준으로
    @discardableResult
    func setPin(_ p: String) -> Bool {
        guard PinVault.set(p) else { return false }
        if st.pin != nil { update { $0.pin = nil } }
        Biometry.accept()
        return true
    }

    func scenePhase(_ p: ScenePhase) {
        if p == .background { awayAt = Date() }
        if p == .active, let a = awayAt, Date().timeIntervalSince(a) > 60 {
            if st.onboarded && st.lockEnabled && hasPin { locked = true }
        }
        if p == .active {
            awayAt = nil
            Task { await sync() }
        }
    }

    func update(_ fn: (inout AppState) -> Void) {
        var s = st
        fn(&s)
        st = s
    }

    private func newId(_ p: String) -> String { "\(p)\(Int(Date().timeIntervalSince1970 * 1000))\(Int.random(in: 100...999))" }
    private func newNoti(_ icon: String, _ title: String, _ body: String) -> Noti {
        Noti(id: newId("n"), icon: icon, title: title, body: body, ts: Date(), read: false)
    }

    // MARK: 잔액 동기화

    /// 5초마다: 입금을 기다리는 중이면 15초, 아니면 60초 간격으로 잔액 확인
    private func tick() {
        guard startupReady, st.onboarded, st.addrs != nil, !syncing else { return }
        let since = Date().timeIntervalSince(st.lastSync ?? .distantPast)
        let every = st.deposits.isEmpty ? 60.0 : DepositTiming.checkEvery
        if since >= every { Task { await sync() } }
        markSlowDeposits()
    }

    /// 메인넷에서 잔액·시세 읽기
    func sync() async {
        let target: ChainAddrs? = await MainActor.run {
            if !self.startupReady || self.syncing || self.st.addrs == nil { return nil }
            self.syncing = true
            return self.st.addrs
        }
        guard let a = target else { return }
        let nets = Set(["솔라나", "이더리움", "비트코인", "카르다노"].filter { WalletKeys.passed($0) })
        let wantPrices = Date().timeIntervalSince(lastPriceAt) > 55
        async let balJob = ChainAPI.balances(a, only: nets)
        async let priceJob = ChainAPI.prices(on: wantPrices)
        async let extraJob = MultiChainAPI.fetch(a)
        async let receiptJob: [ChainReceipt]? = ReceiveHistory.all(a, ethereum: nets.contains("이더리움"))
        let bal = await balJob
        let extra = await extraJob
        let quotes = await priceJob
        let receipts = await receiptJob
        let pending = await MainActor.run { self.st.tx.filter { $0.type == .send && $0.inFlight && !$0.hash.isEmpty } }
        var statuses: [String:TxStatus] = [:]
        for tx in pending {
            guard let n = WalletNetwork(rawValue:tx.network) else { continue }
            let status:TxStatus?
            if n == .tron { status = try? await TronTransfer.status(tx.hash) }
            else if n == .solana { status = try? await SolanaTransferEngine.status(tx.hash) }
            else if n == .bitcoin { status = try? await BitcoinTransfer.status(tx.hash) }
            else if n == .cardano { status = try? await CardanoTransfer.status(tx.hash) }
            else { status = try? await EVMTransfer.status(tx.hash,network:n) }
            if let status { statuses[tx.id] = status }
        }
        let retry = await MainActor.run { self.st.addrs == a && self.st.onboarded ? (self.st.pendingBroadcasts ?? []) : [] }
        // 72시간 넘게 확정되지 않은 거래 (보낸 시각 = 내역의 ts)
        let stale: Set<String> = await MainActor.run {
            Set(self.st.tx.filter { $0.type == .send && $0.inFlight && Date().timeIntervalSince($0.ts) > PendingPolicy.staleAfter }.map(\.id))
        }
        var expired = Set<String>()
        for candidate in retry {
            if (try? await TransferDispatcher.expired(candidate)) == true {
                statuses[candidate.network + candidate.id] = .failed
                expired.insert(candidate.network + candidate.id)
            }
        }
        for pending in retry where Date().timeIntervalSince(pending.lastAttempt) > PendingPolicy.retryEvery(stale: stale.contains(pending.network + pending.id))
                                    && (pending.expires == nil || pending.expires! > Date()) {
            guard let network = WalletNetwork(rawValue:pending.network),
                  !statuses.contains(where:{ $0.key == pending.network + pending.id && ($0.value == .done || $0.value == .failed) }),
                  let payload = try? JSONSerialization.jsonObject(with:pending.payload) as? [String:Any] else { continue }
            let valid = await MainActor.run { () -> Bool in
                guard self.st.addrs == a, self.st.onboarded,
                      let i = self.st.pendingBroadcasts?.firstIndex(where:{ $0.id == pending.id && $0.network == pending.network }) else { return false }
                self.update { $0.pendingBroadcasts?[i].lastAttempt = Date() }
                return true
            }
            guard valid else { break }
            try? await TransferDispatcher.broadcast(SignedTransfer(id:pending.id,payload:payload),network:network)
        }
        let finalStatuses = statuses, finalExpired = expired
        await MainActor.run {
            guard self.st.addrs == a, self.st.onboarded else { self.syncing = false; return }
            if quotes != nil { self.lastPriceAt = Date() }
            let before = self.st
            self.apply(bal, quotes, requested: nets)
            self.applyNetworks(extra, legacy: bal)
            self.checkDeposits(before:before)
            if let receipts { self.applyReceipts(receipts) }
            self.update { s in
                for (id,status) in finalStatuses {
                    if let i = s.tx.firstIndex(where:{ $0.id == id }) {
                        // 아직 확인 중인데 72시간이 지났으면 '평소보다 늦음'
                        s.tx[i].status = status == .pending && stale.contains(id) ? .delayed : status
                        if finalExpired.contains(id) {
                            let n = WalletNetwork(rawValue: s.tx[i].network)
                            s.tx[i].via = n == .bitcoin || n?.isEVM == true
                                ? "다른 거래가 먼저 처리돼서 이 송금은 처리되지 않았어요"
                                : "유효 시간이 지나 처리되지 않았어요"
                        }
                        if status == .done || status == .failed { let hash = s.tx[i].hash; let net = s.tx[i].network; s.pendingBroadcasts?.removeAll { $0.id == hash && $0.network == net } }
                    }
                }
            }
            self.syncing = false
        }
    }

    private func apply(_ b: ChainAPI.Balances, _ q: [String: ChainAPI.Quote]?, requested: Set<String>) {
        update { s in
            if let q = q {
                for (k, v) in q { s.prices[k] = v.krw; s.change[k] = v.change }
                if let t = q["usdt"]?.krw, t > 500 { s.usdKrw = t }
            }
            Store.mergeLegacy(&s, b)
            s.syncFailed = b.failed.filter { requested.contains($0) }
            s.lastSync = Date()
        }
        RATE = st.usdKrw
        // Network-specific reconciliation occurs after all balance snapshots are applied.
    }

    static func mergeLegacy(_ s: inout AppState, _ b: ChainAPI.Balances) {
        if let x = b.solana { s.wallet.circle = x.usdc; s.wallet.tether = x.usdt; s.coins["sol"] = x.sol }
        if let x = b.eth { s.coins["eth"] = x }
        if let x = b.btc { s.coins["btc"] = x }
        if let x = b.cardano { s.coins["ada"] = x.ada; s.coins["night"] = x.night }
    }

    private func applyNetworks(_ results: [NetworkSnapshot], legacy: ChainAPI.Balances) {
        update { s in Store.mergeNetworks(&s, results, legacy: legacy) }
    }

    /// 네트워크별 잔액을 상태에 반영 (통장 찾기에서도 같은 계산을 씀)
    static func mergeNetworks(_ s: inout AppState, _ results: [NetworkSnapshot], legacy: ChainAPI.Balances) {
        do {
            var ledger = s.networkBalances ?? [:]
            var dates = s.networkSynced ?? [:]
            var errors = s.networkErrors ?? [:]
            for network in legacy.failed { errors[network] = "잔액 확인 실패" }
            // Legacy readers are display-only until converted to integer transport decoding.
            if let sol = legacy.solana {
                ledger["솔라나"] = ["sol": String(format:"%.0f", sol.sol * 1e9), "usdc": String(format:"%.0f", sol.usdc * 1e6), "usdt": String(format:"%.0f", sol.usdt * 1e6)]
                dates["솔라나"] = Date(); errors.removeValue(forKey:"솔라나")
            }
            if let btc = legacy.btc { ledger["비트코인"] = ["btc":String(format:"%.0f",btc*1e8)]; dates["비트코인"] = Date(); errors.removeValue(forKey:"비트코인") }
            if let cardano = legacy.cardano { ledger["카르다노"] = ["ada":String(format:"%.0f",cardano.ada*1e6),"night":String(format:"%.0f",cardano.night*1e6)]; dates["카르다노"] = Date(); errors.removeValue(forKey:"카르다노") }
            for result in results {
                if let balances = result.balances { ledger[result.network.rawValue] = balances; dates[result.network.rawValue] = Date(); errors.removeValue(forKey:result.network.rawValue) }
                else { errors[result.network.rawValue] = result.error ?? "잔액 확인 실패" }
            }
            s.networkBalances = ledger; s.networkSynced = dates; s.networkErrors = errors
            for asset in ["usdc", "usdt"] {
                let total = WalletNetwork.allCases.reduce(Decimal(0)) { sum, net in
                    guard let raw = ledger[net.rawValue]?[asset] else { return sum }
                    return sum + ExactAmount.display(raw: raw, decimals: net.decimals(asset))
                }
                let value = NSDecimalNumber(decimal: total).doubleValue
                if asset == "usdc" { s.wallet.circle = value } else { s.wallet.tether = value }
            }
            if let raw = ledger["맨틀"]?["usdt0"] { s.coins["usdt0"] = NSDecimalNumber(decimal:ExactAmount.display(raw:raw,decimals:6)).doubleValue }
            if let price = s.prices["usdt"] { s.prices["usdt0"] = price }
            for net in [WalletNetwork.tron, .mantle, .avalanche] {
                if let raw = ledger[net.rawValue]?[net.native] { s.coins[net.native] = NSDecimalNumber(decimal: ExactAmount.display(raw:raw,decimals:net.decimals(net.native))).doubleValue }
            }
        }
    }

    private func applyReceipts(_ receipts:[ChainReceipt]) {
        update { state in
            for receipt in receipts {
                let id = receipt.network.rawValue + receipt.hash + receipt.asset
                guard !state.tx.contains(where:{ $0.id == id || ($0.type == .receive && $0.hash == receipt.hash && $0.assetId == receipt.asset) }) else { continue }
                let quantity = NSDecimalNumber(decimal:ExactAmount.display(raw:receipt.raw,decimals:receipt.network.decimals(receipt.asset))).doubleValue
                if let i = state.tx.firstIndex(where:{ $0.type == .receive && $0.hash.isEmpty && $0.network == receipt.network.rawValue && $0.assetId == receipt.asset && $0.status == .done && abs($0.quantity-quantity) < 0.000001 && abs($0.ts.timeIntervalSince(receipt.date)) < 21600 }) {
                    state.tx[i].hash = receipt.hash; state.tx[i].addr = receipt.sender
                } else {
                    state.tx.insert(Tx(id:id,hash:receipt.hash,type:.receive,addr:receipt.sender,amt:quantity * state.usdPrice(receipt.asset),memo:"",ts:receipt.date,asset:receipt.asset,qty:quantity,net:receipt.network.rawValue,status:.done),at:0)
                }
            }
            state.tx.sort { $0.ts > $1.ts }
        }
    }

    // MARK: 거래소에서 가져오기 — 실제 잔액이 늘어나는지 지켜보기

    @discardableResult
    func startDeposit(asset: String, exchange: String, net: String) -> String {
        let id = newId("t")
        let tx = Tx(id: id, hash: "", type: .receive, addr: nil, amt: 0,
                    memo: "\(exchange)에서 가져오는 중", ts: Date(), asset: asset, qty: nil, net: net, status: .pending, via: exchange)
        update { s in
            s.exRegistered["\(exchange)·\(net)"] = true
            s.deposits.removeAll { $0.asset == asset && $0.net == net }
            s.tx.insert(tx, at: 0)
            // 아직 한 번도 잔액을 못 읽었으면 기준값은 다음 동기화 때 정함 (-1)
            s.deposits.append(Deposit(id: id, asset: asset, exchange: exchange, net: net, start: Date(),
                                      baseline: WalletNetwork(rawValue:net).flatMap { s.balance(asset,net:$0.rawValue) } ?? -1))
        }
        Task { await sync() }
        return id
    }

    /// 기다리기 그만 (내역에서는 지움)
    func cancelDeposit(_ id: String) {
        update { s in
            s.deposits.removeAll { $0.id == id }
            s.tx.removeAll { $0.id == id && $0.status != .done }
        }
    }

    /// 0: 대기 · 1: 거래소 출금 대기 · 2: 네트워크 확인 중 · 3: 도착
    func depositPhase(_ id: String, at now: Date = Date()) -> Int {
        guard let d = st.deposits.first(where: { $0.id == id }) else {
            return st.tx.first(where: { $0.id == id })?.status == .done ? 3 : 0
        }
        return now.timeIntervalSince(d.start) >= DepositTiming.networkPhase ? 2 : 1
    }
    func deposit(_ id: String) -> Deposit? { st.deposits.first { $0.id == id } }

    private func markSlowDeposits() {
        let now = Date()
        for d in st.deposits where now.timeIntervalSince(d.start) >= DepositTiming.slowAfter {
            guard st.tx.first(where: { $0.id == d.id })?.status == .pending else { continue }
            update { s in
                if let i = s.tx.firstIndex(where: { $0.id == d.id }) { s.tx[i].status = .delayed }
                var n = newNoti("time", "\(d.exchange)에서 오는 \(josa(assetFullName(d.asset), "이/가")) 늦어지고 있어요",
                                "거래소 앱 출금 내역에서 상태를 확인해보세요")
                n.action = "tx:\(d.id)|\(s.activeId)"
                n.acct = s.activeId
                if s.inTest { n.test = true }
                s.notifications.insert(n, at: 0)
            }
        }
    }

    /// 동기화 뒤: 잔액이 늘었으면 기다리던 입금 완료 처리, 아니면 '들어왔어요' 알림
    private func checkDeposits(before: AppState) {
        for net in WalletNetwork.allCases {
            guard let currentDate = st.networkSynced?[net.rawValue], currentDate != before.networkSynced?[net.rawValue] else { continue }
            for asset in net.assets {
                guard let now = st.balance(asset,net:net.rawValue) else { continue }
                if let d = st.deposits.first(where:{ $0.asset == asset && $0.net == net.rawValue }) {
                    if d.baseline < 0 { update { s in if let i = s.deposits.firstIndex(where:{ $0.id == d.id }) { s.deposits[i].baseline = now } } }
                    else if now > d.baseline { finishDeposit(d,qty:now-d.baseline) }
                } else if let old = before.balance(asset,net:net.rawValue), before.networkSynced?[net.rawValue] != nil, now > old {
                    // 잔액이 늘었으면 내역에 '받음'으로 남김 (보낸 주소는 모름 · 트론 USDT 는 나중에 거래 해시로 채워짐)
                    let qty = now - old
                    let tx = Tx(id:newId("r"),hash:"",type:.receive,addr:nil,amt:qty * st.usdPrice(asset),memo:"",ts:Date(),asset:asset,qty:qty,net:net.rawValue,status:.done)
                    update { $0.tx.insert(tx, at: 0) }
                    if st.notify["receive"] ?? true {
                        let title = "\(assetFullName(asset)) \(josa(assetAmount(asset,qty), "이/가")) 들어왔어요"
                        var n = newNoti("arrow-down",title,"\(net.rawValue) 네트워크 · 잔액에 반영했어요")
                        n.action = Store.assetAction(asset, account: st.activeId)
                        n.acct = st.activeId
                        if st.inTest { n.test = true }
                        update { $0.notifications.insert(n,at:0) }
                    }
                }
            }
        }
    }

    /// 알림을 누르면 갈 곳 — "asset:<자산>|<통장 id>"
    static func assetAction(_ asset: String, account: String) -> String { "asset:\(asset)|\(account)" }

    private func finishDeposit(_ d: Deposit, qty: Double) {
        let usd = qty * st.usdPrice(d.asset)
        let title = "\(d.exchange)에서 \(josa(assetFullName(d.asset), "이/가")) 들어왔어요"
        update { s in
            s.deposits.removeAll { $0.id == d.id }
            if let i = s.tx.firstIndex(where: { $0.id == d.id }) {
                s.tx[i].status = .done
                s.tx[i].qty = qty
                s.tx[i].amt = usd
                s.tx[i].ts = Date()
                s.tx[i].memo = "\(d.exchange)에서 가져옴"
            }
            var n = newNoti("arrow-down", title, "\(assetAmount(d.asset, qty)) · \(d.net) 네트워크")
            n.action = Store.assetAction(d.asset, account: s.activeId)
            n.acct = s.activeId
            if s.inTest { n.test = true }
            s.notifications.insert(n, at: 0)
        }
        haptic(.success)
        toast(title, "arrow-down-circle")
    }

    // MARK: 이전 송금·이자 경로 (비활성)

    func send(to: String, amt: Double, memo: String, prefer: String?) {}
    func sendFailed(to: String, amt: Double, memo: String, prefer: String?) {}
    func saveIn(_ amt: Double) {}
    func saveOut(_ amt: Double) {}

    func saveRecipient(network:String,address:String,name:String) {
        let r = SavedRecipient(network:network,address:address,name:name.trimmingCharacters(in:.whitespaces))
        guard !r.name.isEmpty, let n = WalletNetwork(rawValue:network), WalletKeys.valid(address,network:n) else { return }
        update { s in
            var saved = s.savedRecipients ?? []; saved.removeAll { $0.id == r.id }; saved.append(r); s.savedRecipients = saved
        }
    }
    func recordTransfer(_ quote:TransferQuote,signed:SignedTransfer) {
        let qty = NSDecimalNumber(decimal:ExactAmount.display(raw:quote.raw,decimals:quote.network.decimals(quote.asset))).doubleValue
        let tx = Tx(id:quote.network.rawValue + signed.id,hash:signed.id,type:.send,addr:quote.recipient,amt:qty * st.usdPrice(quote.asset),memo:"",ts:Date(),asset:quote.asset,qty:qty,net:quote.network.rawValue,status:.pending,feeUpper:NSDecimalNumber(decimal:quote.fee).stringValue + " " + quote.network.native.uppercased(),via:"전파 확인 중")
        guard let payload = try? JSONSerialization.data(withJSONObject:signed.payload) else { return }
        var pending = PendingBroadcast(id:signed.id,network:quote.network.rawValue,payload:payload,expires: quote.network == .tron ? (((signed.payload["raw_data"] as? [String:Any])?["expiration"] as? NSNumber).map { Date(timeIntervalSince1970:$0.doubleValue/1000) }) : nil,lastAttempt:Date(),validHeight:quote.draft["validHeight"] as? UInt64,validSlot:quote.draft["validSlot"] as? UInt64)
        if quote.network.isEVM { pending.owner = quote.owner; pending.nonce = quote.draft["nonce"] as? String }
        if quote.network == .bitcoin { pending.inputs = BitcoinTransfer.spentInputs(quote) }
        update { s in
            if !s.tx.contains(where:{ $0.id == tx.id }) { s.tx.insert(tx,at:0) }
            var saved = s.pendingBroadcasts ?? []; saved.removeAll { $0.id == pending.id && $0.network == pending.network }; saved.append(pending); s.pendingBroadcasts = saved
        }
    }

    // MARK: 기타

    func setContact(_ addr: String, _ name: String) { update { $0.contacts[addr] = Contact(name: name) } }
    func removeContact(_ addr: String) { update { _ = $0.contacts.removeValue(forKey: addr) } }
    func setMemo(_ id: String, _ memo: String) {
        update { s in
            if let i = s.tx.firstIndex(where: { $0.id == id }) { s.tx[i].memo = memo }
        }
    }
    func applyCard() {
        update { s in
            s.card = CardState(status: "applied", queue: 1284)
            s.notifications.insert(newNoti("card", "카드 사전 신청이 완료됐어요", "발급이 시작되면 가장 먼저 알려드릴게요"), at: 0)
        }
    }
    func cancelCard() { update { $0.card = CardState(status: "none", queue: nil) } }
    func addSchedule(to: String, amt: Double, day: Int, memo: String) {
        update { $0.schedules.append(Schedule(id: newId("s"), to: to, amt: amt, day: day, memo: memo)) }
    }
    func removeSchedule(_ id: String) { update { $0.schedules.removeAll { $0.id == id } } }
    func readAll() {
        update { s in
            let test = s.inTest
            for i in s.notifications.indices where (s.notifications[i].test == true) == test { s.notifications[i].read = true }
        }
    }

    func markBackedUp() {
        update { s in
            s.backedUp = true
            if let w = s.currentWallet?.id, let i = s.wallets?.firstIndex(where: { $0.id == w }) {
                s.wallets?[i].backedUp = true
                s.wallets?[i].backedUpAt = Date()
            }
            s.notifications.removeAll { $0.action == "recovery" }
        }
    }

    /// 지금 통장이 아닌 지갑의 12단어를 적었을 때
    func markBackedUp(wallet id: String) {
        if id == st.currentWallet?.id { markBackedUp(); return }
        update { s in
            if let i = s.wallets?.firstIndex(where: { $0.id == id }) {
                s.wallets?[i].backedUp = true
                s.wallets?[i].backedUpAt = Date()
            }
        }
    }

    // MARK: 시작 / 지우기

    /// 온보딩 끝: 실제 주소로 시작 (키는 이미 Keychain 에 있음)
    /// 비밀번호를 Keychain 에 저장하지 못하면 false — 평문으로 남기지 않고 다시 시도하게 함
    @discardableResult
    func finishOnboarding(addrs: ChainAddrs, restored: Bool, pin: String, bio: Bool, backedUp: Bool = false) -> Bool {
        guard PinVault.set(pin) else { return false }
        Biometry.accept()
        WalletKeys.clearFresh()
        var s = AppState()
        s.addrs = addrs
        s.backedUp = restored || backedUp // 복구 또는 퀴즈 확인 완료
        s.onboarded = true
        s.bio = bio
        if !s.backedUp {
            s.notifications = [Noti(id: "backup-reminder", icon: "key", title: "복구 문구를 적어주세요",
                                    body: "돈을 넣기 전에 종이에 적어두세요", ts: Date(), read: true, action: "recovery")]
        } else if restored {
            s.notifications = [Noti(id: "n0", icon: "key", title: "지갑을 되찾았어요",
                                    body: "열쇠는 이 폰 안에만 있어요", ts: Date(), read: true)]
        }
        hasSavedKey = true
        st = s
        migrateAccounts(main: addrs)
        applySlot()
        Task { await sync() }
        return true
    }

    /// 이 폰에서 지갑 지우기 (Keychain 의 복구 문구까지)
    /// Keychain 에서 지운 게 확인될 때만 앱 상태를 지움. 실패하면 false (상태는 그대로)
    @discardableResult
    func wipe() -> Bool {
        for w in st.walletList where !w.isMain {
            guard WalletKeys.deleteWallet(w.id) else { return false }
            update { s in
                s.accounts?.removeAll { $0.walletId == w.id }
                s.wallets?.removeAll { $0.id == w.id }
            }
        }
        guard WalletKeys.delete() else { return false }
        PinVault.delete()
        Biometry.forget()
        UserDefaults.standard.removeObject(forKey: Store.key)
        WalletKeys.active = KeySlot()
        Testnet.on = false
        hasSavedKey = false
        locked = false
        st = AppState()
        return true
    }
}
