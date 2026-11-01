import SwiftUI

// App.js의 Stack / Tab 구조

enum Route: Hashable {
    case dollar
    case savings
    case savingsMove(String) // "in" | "out"
    case txDetail(String)
    case contacts
    case contactDetail(String)
    case notifications
    case recovery
    case homeEdit
    case coin(String)
    case coins
    case schedules
    case changePin
    case card
    case walletPhrase(String) // 그 지갑의 12단어
    case faucet               // 테스트 토큰 받기
    case walletDetail(String, String) // 주소, 네트워크 — 이름 없는 지갑 상세
    case coinHistory(String)          // 코인 내역 전체 보기
}

/// 아래에서 올라오는 전체 화면 (fullScreenModal)
enum Modal: Identifiable, Equatable {
    case send(req: PayRequest?, k: Int)
    case receive
    case fromExchange(asset: String?)
    case scan
    case nearby
    case addWallet

    var id: String {
        switch self {
        case .send(let r, let k): return "send-\(r?.to ?? "")-\(k)"
        case .receive: return "receive"
        case .fromExchange(let a): return "fx-\(a ?? "")"
        case .scan: return "scan"
        case .nearby: return "nearby"
        case .addWallet: return "addWallet"
        }
    }
}

enum AppTab: Int, CaseIterable {
    case home, history, contacts, more
    var label: String { ["홈", "내역", "주소록", "전체"][rawValue] }
    var icon: String { ["home", "receipt", "people", "menu"][rawValue] }
}

final class Router: ObservableObject {
    @Published var path: [Route] = []
    @Published var modal: Modal? = nil
    @Published var contactEdit = false
    @Published var tab: AppTab = .home
    @Published var accountSheet = false   // 통장 고르기
    /// 받기를 열 때 바로 이 코인의 QR 로 (코인 상세의 '받기')
    var receiveAsset: String? = nil
    func receive(_ asset: String) { receiveAsset = asset; present(.receive) }

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    private var pendingModal: Modal?

    func present(_ m: Modal) {
        guard modal != m else { return }
        if pendingModal != nil {
            pendingModal = m
        } else if modal != nil {
            pendingModal = m
            modal = nil
        } else {
            modal = m
        }
    }

    /// 탭 바 가운데 O 위치 (전역 좌표) — QR 찍기 링이 여기서 커져 나옴
    var payButtonFrame: CGRect = .zero
    private(set) var scanLaunch: CGRect? = nil

    /// 가운데 O 로 QR 찍기: 아래서 올라오는 기본 전환 없이, 링이 O 자리에서 시작
    func openScanFromO() {
        scanLaunch = payButtonFrame == .zero ? nil : payButtonFrame
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { present(.scan) }
    }

    func modalDidDismiss() {
        scanLaunch = nil
        guard let next = pendingModal else { return }
        pendingModal = nil
        modal = next
    }
    func sendTo(_ addr: String?) { send(addr.map { PayRequest(to: $0) }) }
    /// 받는 사람·금액·자산이 정해진 채로 보내기 열기 (QR 요청, 다시 보내기)
    func send(_ req: PayRequest?) { present(.send(req: req, k: Int(Date().timeIntervalSince1970 * 1000))) }
}
