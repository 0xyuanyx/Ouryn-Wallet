"""Exercise the production prepare method with deterministic storage/network boundaries."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
s = (root/'Ouryn/Core/Store.swift').read_text()
prepare = s.split('    @MainActor\n    func prepare()', 1)[1].split('    private func save()', 1)[0]
code = '''
import Foundation
// Storage and network boundaries are fakes; the prepare method below is unchanged product code.
enum SavedKeyStatus { case available, missing, unavailable }
enum WalletKeys {
    static var status: SavedKeyStatus = .unavailable
    static var selfTest = true
    static func openExisting(reason: String? = nil) -> String? { nil }
    static func savedKeyStatus() -> SavedKeyStatus { status }
    static var staged: [String] = []
    static var migrated: [String] = []
    static func recoverStaged(wallets: [String]) { staged = wallets }
    static func isBiometric(_ wallet: String = "main") -> Bool { false }
    static func migrateProtection(wallets: [String]) { migrated = wallets }
}
struct WalletBoxFake: Equatable { var id: String }
// Keychain 비밀번호 저장소 대역 (메모리)
enum PinVault {
    static var saved: String? = nil
    static var exists: Bool { saved != nil }
    @discardableResult static func set(_ p: String) -> Bool { saved = p; return true }
    @discardableResult static func delete() -> Bool { saved = nil; return true }
}
struct AppState: Equatable {
    var addrs: String? = nil
    var onboarded = false
    var lockEnabled = true
    var pin: String? = nil
    var marker = ""
    var walletList: [WalletBoxFake] = [WalletBoxFake(id: "main")]
}
final class Store {
    var st = AppState()
    var locked = false
    var startupReady = false
    var startupError: String?
    var hasSavedKey = false
    var preparing = false
    func sync() async {}
    func restoreAccounts(main: String) { st.addrs = main }
    func restoreAccountsFromCache() {}
    var hasPin: Bool { st.pin != nil || PinVault.exists }
    func update(_ fn: (inout AppState) -> Void) { var s = st; fn(&s); st = s }
    @MainActor
    func prepare()''' + prepare + '''
}
@main struct Run {
    @MainActor static func main() async {
        let store = Store()
        let saved = AppState(onboarded: true, lockEnabled: true, pin: "test-fixture", marker: "preserve-me")
        store.st = saved
        await store.prepare()
        precondition(store.st == saved, "Inaccessible Keychain must preserve saved state")
        precondition(!store.startupReady && store.startupError != nil && !store.preparing)
        WalletKeys.status = .available
        await store.prepare()
        var migrated = saved; migrated.pin = nil
        precondition(store.st == migrated && PinVault.saved == "test-fixture", "Legacy PIN must move to the Keychain vault")
        precondition(store.startupReady && store.locked && store.hasSavedKey)
        precondition(store.startupError == nil)
        precondition(WalletKeys.staged == ["main"] && WalletKeys.migrated == ["main"], "Startup must recover staged keys and migrate protection")
        WalletKeys.status = .missing
        await store.prepare()
        precondition(store.st == migrated, "Ready store must not initialize again")
        let missing = Store()
        missing.st = saved
        await missing.prepare()
        precondition(missing.st == AppState() && missing.startupReady && !missing.locked && !missing.hasSavedKey)
        precondition(PinVault.saved == nil, "Absent wallet key must also drop the orphan PIN")
        print("PASS: unavailable preserves state; retry succeeds and migrates PIN; ready is idempotent; absent key resets state and PIN")
    }
}
'''
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp)
    (p/'startup.swift').write_text(code)
    subprocess.run(['swiftc','-module-cache-path','/tmp/ouryn-swift-cache','-parse-as-library',str(p/'startup.swift'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
