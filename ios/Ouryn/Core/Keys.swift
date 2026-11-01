import Foundation
import Security
import LocalAuthentication
import CryptoKit
import WalletCore

// 실제 지갑 키 — Trust Wallet Core (https://github.com/trustwallet/wallet-core)
// - 복구 문구(영어 12단어, BIP39)는 이 폰의 Keychain 에만 저장 (iCloud 동기화·백업 제외)
// - Keychain 항목에 생체인증 조건(.biometryAny)을 걸어서 Face ID 를 통과해야만 12단어가 나옴 (아이폰 암호로는 대신 못 엶)
//   얼굴 등록이 바뀌면(Biometry) 앱 비밀번호를 한 번 더 물음 · Face ID 를 못 쓰면 12단어를 직접 입력해서 서명
// - 주소는 다른 지갑과 같은 표준 경로로 파생
//     솔라나   m/44'/501'/0'/0'   (Phantom·Solflare 와 같음)
//     이더리움 m/44'/60'/0'/0/0   (MetaMask 와 같음)
//     비트코인 m/84'/0'/0'/0/0    (네이티브 세그윗 bc1q…)
//     카르다노 m/1852'/1815'/0'/0/0 (Shelley 기본 주소 addr1q…, 스테이킹 키 포함)
// - 앱을 켤 때 알려진 테스트 문구로 주소를 계산해 정답과 비교 → 틀린 체인은 주소를 보여주지 않음

struct ChainAddrs: Codable, Equatable {
    var solana: String
    var ethereum: String
    var bitcoin: String
    var cardano: String
    var tron: String? = nil
}

enum SavedKeyStatus {
    case available, missing, unavailable
}

/// 12단어 꺼내기 결과
enum KeyUnlock {
    case words(String)
    case cancelled   // Face ID 창에서 취소
    case failed      // Face ID 실패·못 씀, 항목 없음
}

/// 보내기 전 본인 확인 — faceID: Face ID 만 · pin: 앱 비밀번호 먼저 · words: 12단어만
enum SendGate { case faceID, pin, words }

/// 주소 계산 방식 — 같은 12단어라도 앱마다 경로가 조금 다름
/// standard: Ouryn · Phantom · MetaMask (솔라나 m/44'/501'/n'/0', 이더리움 m/44'/60'/0'/0/n)
/// alt: Trust Wallet · Ledger (솔라나 m/44'/501'/n', 이더리움 m/44'/60'/n'/0/0)
enum KeyScheme: String, Codable { case standard, alt }

/// 지금 쓰는 통장 = 어느 지갑(12단어)의 몇 번째 계정인지. Store 가 통장을 바꿀 때 맞춤
struct KeySlot: Equatable {
    var wallet = "main"
    var index = 0
    var scheme = KeyScheme.standard
    /// 테스트 통장 — 비트코인은 테스트넷 경로(m/84'/1'/n'), 비트코인·카르다노 주소는 테스트넷 표기
    var test = false
    var isLegacy: Bool { index == 0 && scheme == .standard && !test }
}

enum WalletKeys {
    private static let service = "com.yuanyx.ouryn.wallet"
    private static let account = "mnemonic"

    // MARK: 만들기 · 불러오기

    /// 새 지갑: 12단어 생성 → Keychain 저장 → 주소
    static func create() -> ChainAddrs? {
        guard let w = HDWallet(strength: 128, passphrase: "") else { return nil }
        guard save(w.mnemonic) else { return nil }
        freshWords = w.mnemonic.split(separator: " ").map(String.init)
        return addrs(w)
    }

    /// 방금 만든 지갑의 12단어 — 온보딩에서 적고 확인하는 동안만 메모리에 둠 (Face ID 를 또 띄우지 않으려고)
    private(set) static var freshWords: [String] = []
    static func clearFresh() { freshWords = [] }

    /// 복구 문구로 되찾기 (검증 후 저장)
    static func restore(_ words: String) -> ChainAddrs? {
        let m = normalize(words)
        guard isValid(m), let w = HDWallet(mnemonic: m, passphrase: "") else { return nil }
        guard save(m) else { return nil }
        return addrs(w)
    }

    /// 이 폰 Keychain 에 이미 있는 지갑 열기
    /// reason 이 있으면 Face ID 를 띄움(온보딩), 없으면 조용히 — 생체인증 항목은 nil. 백그라운드 스레드에서 부를 것
    static func openExisting(reason: String? = nil) -> ChainAddrs? {
        let ctx: LAContext? = reason.map { authContext($0) }
        guard let m = read("main", ctx).0, let w = HDWallet(mnemonic: m, passphrase: "") else { return nil }
        return addrs(w)
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "," })
            .joined(separator: " ")
    }

    static func isValid(_ words: String) -> Bool { Mnemonic.isValid(mnemonic: normalize(words)) }
    static func isValidWord(_ w: String) -> Bool { Mnemonic.isValidWord(word: w.lowercased()) }

    /// A temporarily inaccessible Keychain must never be treated as an absent wallet.
    /// 12단어는 읽지 않고 항목 정보만 봄 → Face ID 를 띄우지 않음
    static func savedKeyStatus() -> SavedKeyStatus {
        switch attributes("main") {
        case .found: return .available
        case .missing: return .missing
        // 생체인증 항목이 정보 조회도 막는 경우: 같은 보호 수준의 비밀번호 항목이 읽히면 폰은 잠금 해제 상태 → 항목은 있음
        case .protected: return PinVault.exists ? .available : .unavailable
        case .error: return .unavailable
        }
    }

    // MARK: 통장 (계정 번호)

    static var active = KeySlot()

    static func path(_ coin: CoinType, _ index: Int, _ scheme: KeyScheme, test: Bool = false) -> String {
        switch coin {
        case .bitcoin where test: return "m/84'/1'/\(index)'/0/0"
        case .solana: return scheme == .alt ? "m/44'/501'/\(index)'" : "m/44'/501'/\(index)'/0'"
        case .ethereum: return scheme == .alt ? "m/44'/60'/\(index)'/0/0" : "m/44'/60'/0'/0/\(index)"
        case .bitcoin: return "m/84'/0'/\(index)'/0/0"
        case .cardano: return "m/1852'/1815'/\(index)'/0/0"
        case .tron: return "m/44'/195'/\(index)'/0/0"
        default: return coin.derivationPath()
        }
    }

    /// 서명 키 — 0번(standard)은 지금까지와 똑같은 함수로
    static func signingKey(_ w: HDWallet, _ coin: CoinType, _ s: KeySlot = active) -> PrivateKey {
        if s.isLegacy {
            switch coin {
            case .solana: return w.getKey(coin: .solana, derivationPath: "m/44'/501'/0'/0'")
            case .bitcoin: return w.getKey(coin: .bitcoin, derivationPath: "m/84'/0'/0'/0/0")
            default: return w.getKeyForCoin(coin: coin)
            }
        }
        return w.getKey(coin: coin, derivationPath: path(coin, s.index, s.scheme, test: s.test))
    }

    static func signingAddress(_ w: HDWallet, _ coin: CoinType, _ s: KeySlot = active) -> String {
        if s.isLegacy {
            switch coin {
            case .solana: return w.getAddressDerivation(coin: .solana, derivation: .solanaSolana)
            case .bitcoin: return w.getAddressDerivation(coin: .bitcoin, derivation: .bitcoinSegwit)
            default: return w.getAddressForCoin(coin: coin)
            }
        }
        let a = coin.deriveAddress(privateKey: signingKey(w, coin, s))
        if s.test && coin == .bitcoin { return Testnet.btcTest(a) }
        if s.test && coin == .cardano { return Testnet.cardanoTest(a) }
        return a
    }

    /// 그 통장의 주소들
    static func addrs(_ w: HDWallet, slot s: KeySlot) -> ChainAddrs {
        if s.isLegacy { return addrs(w) }
        return ChainAddrs(solana: signingAddress(w, .solana, s), ethereum: signingAddress(w, .ethereum, s),
                          bitcoin: signingAddress(w, .bitcoin, s), cardano: signingAddress(w, .cardano, s),
                          tron: signingAddress(w, .tron, s))
    }

    /// 조용히 계산 — 예전 항목(보호 없음)만 됨. 업데이트 직후 주소 맞추기용
    static func addrs(slot s: KeySlot) -> ChainAddrs? {
        guard let m = load(wallet: s.wallet), let w = HDWallet(mnemonic: m, passphrase: "") else { return nil }
        return addrs(w, slot: s)
    }

    /// 통장 추가처럼 12단어가 꼭 필요할 때 — 생체인증 항목이면 Face ID
    static func addrs(slot s: KeySlot, reason: String) async -> ChainAddrs? {
        guard case .words(let m) = await unlock(wallet: s.wallet, reason: reason),
              let w = HDWallet(mnemonic: m, passphrase: "") else { return nil }
        return addrs(w, slot: s)
    }

    /// 12단어 문구로 계산 (가져오기 전 미리보기 · 저장 안 함)
    static func addrs(words: String, slot s: KeySlot) -> ChainAddrs? {
        let m = normalize(words)
        guard isValid(m), let w = HDWallet(mnemonic: m, passphrase: "") else { return nil }
        return addrs(w, slot: s)
    }

    // MARK: 지갑 (12단어) 더하기

    /// 새 지갑: 12단어를 만들어 저장하고 id 를 돌려줌
    static func createExtra(id: String) -> ChainAddrs? {
        guard let w = HDWallet(strength: 128, passphrase: ""), save(w.mnemonic, wallet: id) else { return nil }
        return addrs(w)
    }

    /// 다른 앱 지갑 가져오기: 12단어 저장
    static func saveExtra(words: String, id: String) -> Bool {
        let m = normalize(words)
        guard isValid(m) else { return false }
        return save(m, wallet: id)
    }

    /// 12단어로 확인했는데 이 폰의 항목이 없어졌으면(Face ID 초기화 등) 다시 저장
    static func repair(words: String, wallet: String) {
        guard !exists(wallet: wallet), isValid(words) else { return }
        _ = put(normalize(words), wallet: wallet)
    }

    /// 이미 이 폰에 있는 지갑과 같은 12단어인지
    /// 12단어 대신 저장해 둔 지문(SHA-256)으로 비교 → Face ID 없이, Face ID 가 고장 나도 확인 가능
    static func holds(_ words: String, wallet: String) -> Bool {
        let m = normalize(words)
        switch attributes(wallet) {
        case .found(_, let mark?): return mark == fingerprint(m)
        case .found(_, nil): return load(wallet: wallet) == m   // 지문 없는 예전 항목 (보호 없음 → 조용히 읽힘)
        default: return false
        }
    }

    /// 지우고, 정말 없어졌는지 다시 확인. 없어졌으면 true
    @discardableResult
    static func deleteWallet(_ id: String) -> Bool {
        _ = SecItemDelete(query(wallet: id, staging: true) as CFDictionary)
        return remove(query(wallet: id))
    }

    private static func addrs(_ w: HDWallet) -> ChainAddrs {
        let sol: String? = w.getAddressDerivation(coin: .solana, derivation: .solanaSolana)
        let eth: String? = w.getAddressForCoin(coin: .ethereum)
        let btc: String? = w.getAddressDerivation(coin: .bitcoin, derivation: .bitcoinSegwit)
        let ada: String? = w.getAddressForCoin(coin: .cardano)
        return ChainAddrs(solana: sol ?? "", ethereum: eth ?? "", bitcoin: btc ?? "", cardano: ada ?? "", tron: w.getAddressForCoin(coin: .tron))
    }

    // MARK: 자체 검사 (알려진 정답과 비교)

    private static let testWords = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    /// 다른 구현(bip_utils)으로 계산해 둔 정답 — Phantom·MetaMask 등과 같은 값
    private static let expected = ChainAddrs(
        solana: "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk",
        ethereum: "0x9858EfFD232B4033E47d90003D41EC34EcaEda94",
        bitcoin: "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
        cardano: "addr1qy8ac7qqy0vtulyl7wntmsxc6wex80gvcyjy33qffrhm7sh927ysx5sftuw0dlft05dz3c7revpf7jx0xnlcjz3g69mq4afdhv")

    /// 네트워크 이름 → 검사 통과 여부
    static let selfTest: [String: Bool] = {
        guard let w = HDWallet(mnemonic: testWords, passphrase: "") else {
            return ["솔라나": false, "이더리움": false, "비트코인": false, "카르다노": false]
        }
        let a = addrs(w)
        // 테스트 통장 0번: 비트코인 m/84'/1'/0'/0/0 · 카르다노 preprod (bip_utils 로 계산한 정답)
        let t = addrs(w, slot: KeySlot(test: true))
        return [
            "테스트넷": t.bitcoin == "tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl"
                && t.cardano == "addr_test1qq8ac7qqy0vtulyl7wntmsxc6wex80gvcyjy33qffrhm7sh927ysx5sftuw0dlft05dz3c7revpf7jx0xnlcjz3g69mqkt5dmn",
            "솔라나": a.solana == expected.solana,
            "이더리움": a.ethereum == expected.ethereum,
            "비트코인": a.bitcoin == expected.bitcoin,
            "카르다노": a.cardano == expected.cardano,
            "트론": a.tron == "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH",
            "맨틀": a.ethereum == expected.ethereum,
            "Avalanche C-Chain": a.ethereum == expected.ethereum,
        ]
    }()
    static func passed(_ net: String) -> Bool { selfTest[net] ?? false }
    static var allPassed: Bool { selfTest.values.allSatisfy { $0 } }

    /// test: 테스트넷 주소로 볼지 (기본은 지금 통장 기준)
    static func valid(_ address: String, network: WalletNetwork, test: Bool = Testnet.on) -> Bool {
        // 테스트넷: 비트코인은 tb1…, 카르다노는 addr_test1… 만
        if test && network == .bitcoin {
            return address.lowercased().hasPrefix("tb1") && AnyAddress(string: Testnet.btcCore(address), coin: .bitcoin) != nil
        }
        if test && network == .cardano {
            guard address.hasPrefix("addr_test1"), let b = Testnet.cardanoBytes(address), b.count >= 29 else { return false }
            return b[b.startIndex] & 0x0F == 0
        }
        let coin: CoinType
        switch network {
        case .tron: coin = .tron
        case .solana: coin = .solana
        case .ethereum, .mantle, .avalanche: coin = .ethereum
        case .bitcoin: coin = .bitcoin
        case .cardano: coin = .cardano
        }
        return AnyAddress(string: address, coin: coin) != nil
    }
    static func tronHex(_ address: String) -> String? {
        guard let a = AnyAddress(string: address, coin: .tron) else { return nil }
        return a.data.map { String(format: "%02x", $0) }.joined()
    }

    static func signTron(_ quote: TransferQuote) throws -> SignedTransfer {
        guard quote.network == .tron, quote.expires > Date(), let wallet = signingWallet(),
              signingAddress(wallet, .tron) == quote.owner,
              let owner = tronHex(quote.owner), let to = tronHex(quote.recipient),
              TronDraftValidator.valid(quote.draft,owner:owner,to:to,raw:quote.raw,
                contract:quote.asset == "usdt" ? tronHex(WalletNetwork.tron.contract("usdt")!) : nil,
                parameter:quote.parameter,maxFee:quote.maxFee,now:Int64(Date().timeIntervalSince1970*1000))
        else { throw TransferError.invalid("전송 확인이 만료됐거나 지갑을 열 수 없어요") }
        guard let header = quote.draft["ouryn_block_header"] as? [String:Any],
              let number = header["number"] as? NSNumber,
              let timestamp = header["timestamp"] as? NSNumber,
              let root = header["txTrieRoot"] as? String, let rootData = Data(hexString:root),
              let parent = header["parentHash"] as? String, let parentData = Data(hexString:parent),
              let witness = header["witness_address"] as? String, let witnessData = Data(hexString:witness),
              let quantity = Int64(quote.raw), let amountData = ExactAmount.bytes(quote.raw)
        else { throw TransferError.invalid("블록 정보가 올바르지 않아요") }
        let input = TronSigningInput.with {
            $0.privateKey = signingKey(wallet, .tron).data
            $0.transaction = TronTransaction.with {
                $0.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                $0.expiration = $0.timestamp + 180000
                $0.feeLimit = quote.asset == "usdt" ? quote.maxFee : 0
                $0.blockHeader = TronBlockHeader.with {
                    $0.timestamp = timestamp.int64Value; $0.number = number.int64Value
                    $0.txTrieRoot = rootData; $0.parentHash = parentData; $0.witnessAddress = witnessData
                    $0.version = (header["version"] as? NSNumber)?.int32Value ?? 0
                }
                if quote.asset == "usdt" {
                    $0.transferTrc20Contract = TronTransferTRC20Contract.with {
                        $0.ownerAddress = quote.owner; $0.toAddress = quote.recipient
                        $0.contractAddress = WalletNetwork.tron.contract("usdt")!; $0.amount = amountData
                    }
                } else {
                    $0.transfer = TronTransferContract.with { $0.ownerAddress = quote.owner; $0.toAddress = quote.recipient; $0.amount = quantity }
                }
            }
        }
        let output: TronSigningOutput = AnySigner.sign(input:input,coin:.tron)
        guard output.error == .ok, let data = output.json.data(using:.utf8),
              let payload = try JSONSerialization.jsonObject(with:data) as? [String:Any]
        else { throw TransferError.invalid("전송 요청 서명 검증에 실패했어요") }
        return SignedTransfer(id:output.id.map { String(format:"%02x",$0) }.joined(),payload:payload)
    }

    // MARK: 서명

    /// 서명하는 동안만 잠깐 들고 있는 지갑. TransferFlow 가 Face ID 또는 12단어로 연 뒤 withSigner 로 넣고, 끝나면 바로 비움
    /// → Keychain 을 조용히 읽어서 서명하는 길은 없음
    private static var signer: HDWallet?

    static func withSigner<T>(_ w: HDWallet, _ body: () throws -> T) rethrows -> T {
        signer = w
        defer { signer = nil }
        return try body()
    }

    // Returns a temporary WalletCore object only to local signing adapters.
    static func signingWallet() -> HDWallet? { signer }

    // MARK: 12단어 꺼내기 (Face ID)

    /// 지갑의 12단어를 꺼냄. 생체인증 항목이면 iOS 가 Face ID 를 띄움 (아이폰 암호로 넘어가는 버튼 없음)
    static func unlock(wallet: String, reason: String) async -> KeyUnlock {
        let ctx = authContext(reason)
        let (m, status) = await Task.detached(priority: .userInitiated) { WalletKeys.read(wallet, ctx) }.value
        if let m { return .words(m) }
        return status == errSecUserCanceled ? .cancelled : .failed
    }

    /// 생체인증으로 보호된 항목인지 (아니면 예전처럼 잠금 해제만으로 읽히는 항목)
    static func isBiometric(_ wallet: String = "main") -> Bool {
        switch attributes(wallet) {
        case .found(let label, _): return label == bioLabel
        case .protected: return true
        default: return false
        }
    }

    static func exists(wallet: String = "main") -> Bool {
        switch attributes(wallet) {
        case .found, .protected: return true
        default: return false
        }
    }

    /// 보내기 전 본인 확인 단계
    /// - 얼굴 등록 그대로: Face ID 만
    /// - 얼굴 등록이 바뀜 또는 생체인증 없는 항목: 앱 비밀번호 먼저 (그다음 Face ID)
    /// - 그 상태에서 비밀번호를 10번 넘게 틀림: 12단어만
    static func sendGate(wallet: String) -> SendGate {
        let bio = isBiometric(wallet)
        let changed = bio && Biometry.changed()
        if PinVault.hardLocked && (changed || !bio) { return .words }
        if changed || !bio { return .pin }
        return .faceID
    }

    // MARK: 저장 방식 옮기기

    /// 예전 항목(보호 없음) → 생체인증 항목. Face ID 가 없는 폰이면 그대로 두고 다음 실행 때 다시 시도
    static func migrateProtection(wallets: [String]) {
        guard biometryEnrolled else { return }
        for id in Set(wallets + ["main"]) {
            guard case .found(let label, _) = attributes(id), label != bioLabel, let m = load(wallet: id) else { continue }
            _ = put(m, wallet: id)
        }
    }

    /// 저장 도중 앱이 꺼졌을 때: 원래 항목이 없고 임시 사본만 있으면 사본으로 되살림
    static func recoverStaged(wallets: [String]) {
        for id in Set(wallets + ["main"]) {
            var q = query(wallet: id, staging: true)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
                  let d = out as? Data, let m = String(data: d, encoding: .utf8) else { continue }
            switch attributes(id) {
            case .missing: _ = put(m, wallet: id)
            case .found, .protected: _ = SecItemDelete(query(wallet: id, staging: true) as CFDictionary)
            case .error: break   // 확실하지 않으면 사본을 남겨둠
            }
        }
    }

    // MARK: Keychain

    private static let bioLabel = "ouryn-bio"
    private static let plainLabel = "ouryn-plain"

    /// Face ID 가 등록돼 있는지 (여러 번 실패해서 잠깐 잠긴 상태도 등록된 것으로 봄)
    static var biometryEnrolled: Bool {
        var err: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) { return true }
        return err?.code == LAError.biometryLockout.rawValue
    }

    /// 등록된 얼굴 아무거나 (다시 등록해도 유지) · 아이폰 암호로는 대신 못 엶 · 폰 암호를 끄면 iOS 가 항목을 지움
    private static func bioAccess() -> SecAccessControl? {
        SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryAny, nil)
    }

    static func authContext(_ reason: String) -> LAContext {
        let ctx = LAContext()
        ctx.localizedReason = reason
        ctx.localizedCancelTitle = "취소"
        ctx.localizedFallbackTitle = ""
        return ctx
    }

    /// 화면을 띄우지 않는 확인용 — 생체인증 항목은 errSecInteractionNotAllowed 로 돌아옴
    private static func silent() -> LAContext {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        return ctx
    }

    /// 12단어의 SHA-256. 12단어는 128비트라 거꾸로 맞힐 수 없음 → 항목 정보에 같이 저장해서 '같은 지갑인지'만 확인
    private static func fingerprint(_ mnemonic: String) -> Data {
        Data(SHA256.hash(data: Data(normalize(mnemonic).utf8)))
    }

    /// main = 처음 만든 Ouryn 지갑 (예전과 같은 항목), 나머지는 mnemonic-<id> · staging = 다시 저장하는 동안의 임시 사본
    private static func query(wallet: String = "main", staging: Bool = false) -> [String: Any] {
        let name = wallet == "main" ? account : account + "-" + wallet
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: staging ? name + ".staging" : name]
    }

    private enum Attr {
        case found(label: String?, mark: Data?)
        case protected   // 있는데 정보 조회도 인증이 필요 (또는 폰이 잠김)
        case missing
        case error
    }

    /// 12단어는 빼고 항목 정보(라벨·지문)만 읽음 → Face ID 를 띄우지 않음
    private static func attributes(_ wallet: String) -> Attr {
        var q = query(wallet: wallet)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationContext as String] = silent()
        var out: AnyObject?
        switch SecItemCopyMatching(q as CFDictionary, &out) {
        case errSecSuccess:
            let a = out as? [String: Any]
            return .found(label: a?[kSecAttrLabel as String] as? String, mark: a?[kSecAttrGeneric as String] as? Data)
        case errSecItemNotFound: return .missing
        case errSecInteractionNotAllowed: return .protected
        default: return .error
        }
    }

    private static func save(_ mnemonic: String, wallet: String = "main") -> Bool {
        put(normalize(mnemonic), wallet: wallet)
    }

    /// 같은 이름의 항목을 새로 저장. 접근 조건은 덮어쓸 수 없어서 지우고 다시 넣음
    /// 지우기 전에 보호 없는 임시 사본을 먼저 두고, 새 항목이 들어간 걸 확인한 뒤 사본을 지움
    /// → 중간에 앱이 꺼져도 다음 실행 때 recoverStaged 가 되살림
    private static func put(_ mnemonic: String, wallet: String) -> Bool {
        let data = Data(mnemonic.utf8), mark = fingerprint(mnemonic)
        let staging = query(wallet: wallet, staging: true)
        _ = SecItemDelete(staging as CFDictionary)
        var s = staging
        s[kSecValueData as String] = data
        s[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(s as CFDictionary, nil) == errSecSuccess else { return false }

        let removed = SecItemDelete(query(wallet: wallet) as CFDictionary)
        guard removed == errSecSuccess || removed == errSecItemNotFound else {
            _ = SecItemDelete(staging as CFDictionary)
            return false
        }
        var ok = false
        if biometryEnrolled, let access = bioAccess() {
            var q = query(wallet: wallet)
            q[kSecValueData as String] = data
            q[kSecAttrAccessControl as String] = access
            q[kSecAttrLabel as String] = bioLabel
            q[kSecAttrGeneric as String] = mark
            ok = SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        }
        if !ok {
            // Face ID 를 못 쓰는 폰(미등록·시뮬레이터): 예전처럼 이 폰에서만, 잠금 해제 상태에서만 → 보낼 때 앱 비밀번호
            var q = query(wallet: wallet)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            q[kSecAttrLabel as String] = plainLabel
            q[kSecAttrGeneric as String] = mark
            ok = SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        }
        if ok { _ = SecItemDelete(staging as CFDictionary) }
        return ok
    }

    /// 조용히 읽기 — 생체인증 항목은 nil (Face ID 를 띄우지 않음)
    private static func load(wallet: String = "main") -> String? { read(wallet, nil).0 }

    /// context 가 있으면 그 context 로 (Face ID 를 띄울 수 있음), 없으면 조용히
    private static func read(_ wallet: String, _ context: LAContext?) -> (String?, OSStatus) {
        var q = query(wallet: wallet)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationContext as String] = context ?? silent()
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess, let d = out as? Data else { return (nil, status) }
        return (String(data: d, encoding: .utf8), status)
    }

    @discardableResult
    static func delete() -> Bool {
        _ = SecItemDelete(query(staging: true) as CFDictionary)
        return remove(query())
    }

    private static func remove(_ q: [String: Any]) -> Bool {
        let status = SecItemDelete(q as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { return false }
        var check = q
        check[kSecUseAuthenticationContext as String] = silent()
        return SecItemCopyMatching(check as CFDictionary, nil) == errSecItemNotFound
    }
}

/// Face ID 등록 상태 — 얼굴이 새로 등록되면 값이 바뀜
/// 마지막으로 본인(앱 비밀번호·12단어)이 확인한 상태를 저장해 두고, 지금과 다르면 앱 비밀번호를 한 번 더 물음
/// (이 비교는 앱 코드가 함. Face ID 자체 판단과 12단어 보호는 iOS 가 함)
enum Biometry {
    private static let service = "com.yuanyx.ouryn.bio"
    private static let account = "enrolled-state"

    /// 지금 등록 상태. Face ID 를 못 쓰면(미등록·잠김) nil
    static func current() -> Data? {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return nil }
        return ctx.evaluatedPolicyDomainState
    }

    /// 마지막 확인 뒤 등록이 바뀌었는지. 기록이 없어도 바뀐 것으로 봄 (업데이트 직후 한 번은 비밀번호)
    /// 지금 Face ID 를 못 쓰면 false — 어차피 Face ID 로는 못 열고 12단어로 감
    static func changed() -> Bool {
        guard let now = current() else { return false }
        return stored() != now
    }

    /// 본인 확인을 마친 흐름에서만 부름 (앱 비밀번호 맞음 · 12단어 확인 · 새 비밀번호 설정)
    static func accept() {
        guard let now = current() else { return }
        let attrs: [String: Any] = [kSecValueData as String: now,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        if SecItemUpdate(query() as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var q = query()
            q.merge(attrs) { _, n in n }
            _ = SecItemAdd(q as CFDictionary, nil)
        }
    }

    static func forget() { _ = SecItemDelete(query() as CFDictionary) }

    private static func stored() -> Data? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
