import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import Combine

/// 외부(서드파티) 키보드는 앱 전체에서 막음 — 12단어·비밀번호 입력을 키보드 앱이 볼 수 없게.
/// 기본 키보드(한국어·영어 등)는 그대로 쓸 수 있음. 은행 앱들이 쓰는 방식
final class OurynAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     shouldAllowExtensionPointIdentifier id: UIApplication.ExtensionPointIdentifier) -> Bool {
        id != .keyboard
    }
}

@main
struct OurynApp: App {
    @UIApplicationDelegateAdaptor(OurynAppDelegate.self) private var appDelegate
    @StateObject private var store = Store()

    init() {
        Fonts.register()
        Appearance.setup()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--multichain-diagnostics") {
                WalletDiagnosticsView().preferredColorScheme(.dark)
            } else {
                RootView().environmentObject(store).preferredColorScheme(.dark)
            }
            #else
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
            #endif
        }
    }
}

enum Appearance {
    static func setup() {
        // 헤더: 배경과 같은 색, 선 없음, 뒤로 버튼은 화살표만
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(C.bg)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.font: uiFont(.sb, 17), .foregroundColor: UIColor(C.text)]
        let back = UIBarButtonItemAppearance()
        back.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
        back.highlighted.titleTextAttributes = [.foregroundColor: UIColor.clear]
        nav.backButtonAppearance = back
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(C.text)
    }
}

// App.js 의 Root
struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            C.bg.ignoresSafeArea()
            if !store.startupReady {
                VStack(spacing: 20) {
                    Image("LaunchLogo").resizable().frame(width: 80, height: 80)
                    if let error = store.startupError {
                        TX(error, .r, 15, C.sub, lh: 22, align: .center)
                        OButton("다시 시도") { Task { await store.prepare() } }
                    } else {
                        ProgressView().tint(C.sub)
                        TX("지갑을 준비하고 있어요", .m, 15, C.sub)
                    }
                }
                .padding(32)
            } else if !store.st.onboarded {
                OnboardingView()
            } else {
                MainNav()
            }
        }
        .task { await store.prepare() }
        .onChange(of: store.startupReady) { _, ready in
            guard ready else { return }
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                Overlays.shared.setup(scene: scene, store: store)
            }
        }
        .onChange(of: phase) { _, p in store.scenePhase(p) }
        // ouryn://scan · ouryn://receive (다이나믹 아일랜드·잠금 화면에서 눌렀을 때)
        .onOpenURL { url in
            if url.scheme == "ouryn", let h = url.host { PendingLink.set(h) }
        }
    }
}

// Stack + 모달
struct MainNav: View {
    @EnvironmentObject var store: Store
    @StateObject private var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            MainTabs()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { r in
                    destination(r)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(C.bg, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .background(C.bg.ignoresSafeArea())
                }
        }
        .tint(C.text)
        .environmentObject(router)
        .fullScreenCover(item: $router.modal, onDismiss: router.modalDidDismiss) { m in
            modalView(m)
                .environmentObject(store)
                .environmentObject(router)
        }
        .oSheet($router.accountSheet) {
            AccountSheet()
                .environmentObject(store)
                .environmentObject(router)
        }
        .sheet(isPresented: $router.contactEdit) {
            ContactEditView()
                .environmentObject(store)
                .environmentObject(router)
        }
        // 결제 모드·제어 센터 버튼으로 열렸으면 바로 그 화면으로
        .onAppear { openPendingLink() }
        .onReceive(NotificationCenter.default.publisher(for: .ourynLink)) { _ in openPendingLink() }
    }

    private func openPendingLink() {
        guard let l = PendingLink.take() else { return }
        switch l {
        case "scan": router.present(.scan)
        case "receive": router.present(.receive)
        default: break
        }
    }

    @ViewBuilder
    private func destination(_ r: Route) -> some View {
        switch r {
        case .dollar: DollarView().navigationTitle("달러")
        case .savings: SavingsView().navigationTitle("이자 모으기")
        case .savingsMove(let mode): SavingsMoveView(mode: mode).navigationTitle(mode == "out" ? "빼기" : "넣기")
        case .txDetail(let id): TxDetailView(id: id).navigationTitle("")
        case .contacts: ContactsView().navigationTitle("주소록")
        case .card: CardView().navigationTitle("카드")
        case .contactDetail(let addr): ContactDetailView(addr: addr).navigationTitle("")
        case .notifications: NotificationsView().navigationTitle("알림")
        case .recovery: RecoveryView().navigationTitle("복구 문구")
        case .walletPhrase(let id): RecoveryView(walletId: id).navigationTitle("복구 문구")
        case .faucet: FaucetView().navigationTitle("")
        case .walletDetail(let a, let n): WalletDetailView(address: a, network: n).navigationTitle("")
        case .coinHistory(let id): CoinHistoryView(id: id).navigationTitle("")
        case .homeEdit: HomeEditView().navigationTitle("홈 목록")
        case .coin(let id): CoinView(id: id).navigationTitle("")
        case .coins: CoinsView().navigationTitle("코인")
        case .schedules: SchedulesView().navigationTitle("자동 보내기")
        case .changePin: ChangePinView().navigationTitle("비밀번호 바꾸기")
        }
    }

    @ViewBuilder
    private func modalView(_ m: Modal) -> some View {
        switch m {
        case .send(let r, _): SendView(initial: r)
        case .receive: ReceiveView()
        case .fromExchange(let asset): FromExchangeView(initialAsset: asset)
        case .scan:
            ScanView(fromSend: false, onPick: { req in router.send(req) }, onMyQR: { router.present(.receive) },
                     launchFrom: router.scanLaunch)
                .presentationBackground(.clear)   // 링이 커지는 동안 뒤 화면이 보이게
        case .nearby: NearbyView(fromSend: false, onPick: { addr in router.sendTo(addr) })
        case .addWallet: AddWalletFlow()
        }
    }
}

// 하단 탭: 홈 · 내역 · ( O ) · 주소록 · 전체
// 가운데 O = 로고. 누르면 QR 찍기, 길게 누르면 메뉴(QR 찍기 · 내 QR)
struct MainTabs: View {
    @EnvironmentObject var router: Router
    @State private var hold = false
    @State private var pressing = false
    @State private var hover: Int? = nil
    @State private var rowFrames: [Int: CGRect] = [:]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabPage(.home) { HomeView() }
                tabPage(.history) { HistoryView() }
                tabPage(.contacts) { ContactsView(embedded: true) }
                tabPage(.more) { MoreView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            tabBar
        }
        .background(C.bg.ignoresSafeArea())
        .overlay { if hold { holdMenu } }
        .animation(.easeOut(duration: 0.18), value: hold)
    }

    private func tabPage<V: View>(_ t: AppTab, @ViewBuilder _ v: () -> V) -> some View {
        v()
            .opacity(router.tab == t ? 1 : 0)
            .allowsHitTesting(router.tab == t)
            .accessibilityHidden(router.tab != t)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.home)
            tabButton(.history)
            Color.clear.frame(maxWidth: .infinity).frame(height: 52)   // 가운데 O 자리
            tabButton(.contacts)
            tabButton(.more)
        }
        .padding(.top, 6)
        .background(C.bg.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(C.line).frame(height: 1) }
        .overlay(alignment: .top) { payButton.offset(y: -24) }   // 탭 바 위로 24pt (원 중심은 예전 자리 그대로)
    }

    private func tabButton(_ t: AppTab) -> some View {
        let on = router.tab == t
        return Button {
            haptic(.select)
            router.tab = t
        } label: {
            VStack(spacing: 3) {
                Icon(on ? t.icon : t.icon + "-outline", 23, on ? C.text : C.mute)
                TX(t.label, .m, 11, on ? C.text : C.mute)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 로고의 열린 O — 지름 80, 어두운 원 + 은색 O
    private var payButton: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: "#26262B"), Color(hex: "#111114")],
                                         center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 56))
            Circle().strokeBorder(Color(hex: "#2E2E35"), lineWidth: 1)
            Logo(size: 80 * LOGO_IN_CIRCLE)
        }
        .frame(width: 80, height: 80)
        .background(Circle().fill(C.bg).padding(-5))   // 탭 바 윗선을 끊어서 떠 있게
        .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { router.payButtonFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in router.payButtonFrame = f }
        })
        .scaleEffect(hold || pressing ? 1.08 : 1)
        .animation(.easeOut(duration: 0.15), value: pressing)
        .contentShape(Circle())
        .overlay(PressCatcher(
            holdAfter: 0.13,
            onDown: { pressing = true },
            onHold: {
                guard pressing else { return }
                haptic(.medium)
                hold = true
            },
            onMove: { p in
                guard hold else { return }
                let i = rowFrames.first(where: { $0.value.contains(p) })?.key
                if i != hover {
                    hover = i
                    if i != nil { haptic(.select) }
                }
            },
            onUp: { moved in
                pressing = false
                if hold {
                    if let i = hover { hover = nil; choose(i) }   // 밀어서 고른 채 떼면 실행, 그냥 떼면 메뉴 유지
                } else if !moved {
                    haptic(.light)
                    router.openScanFromO()
                }
            },
            onCancel: { pressing = false }
        ))
        .accessibilityElement()
        .accessibilityLabel("QR 결제")
        .accessibilityHint("길게 누르면 내 QR을 보여줘요")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { router.openScanFromO() }
        .accessibilityAction(named: "내 QR 보여주기") { router.present(.receive) }
    }

    private func choose(_ i: Int) {
        hold = false
        hover = nil
        if i == 0 { router.openScanFromO() } else { router.present(.receive) }
    }

    private var holdMenu: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "#060608").opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { hold = false; hover = nil }
                .accessibilityLabel("닫기")
                .accessibilityAddTraits(.isButton)
            VStack(spacing: 4) {
                menuRow(0, "scan", "QR 찍기", "누르기만 해도 바로 열려요") { choose(0) }
                menuRow(1, nil, "내 QR 보여주기", "받기 · 코인을 고르면 바로 나와요") { choose(1) }
            }
            .padding(6)
            .frame(width: 260)
            .background(RoundedRectangle(cornerRadius: 20).fill(C.surface2))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(C.surface3, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            .padding(.bottom, 104)
        }
        .transition(.opacity)
    }

    private func menuRow(_ i: Int, _ icon: String?, _ title: String, _ sub: String,
                         _ action: @escaping () -> Void) -> some View {
        Tap(action: action) {
            HStack(spacing: 12) {
                Group {
                    if let icon { Icon(icon, 22, C.text) } else { Logo(size: 22) }
                }
                .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    TX(title, .b, 15)
                    TX(sub, .r, 12, C.sub)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 14).fill(hover == i ? C.faint : (i == 0 ? C.surface3 : Color.clear)))
            .animation(.easeOut(duration: 0.12), value: hover)
        }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { rowFrames[i] = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in rowFrames[i] = f }
        })
    }
}

/// 하단 O 버튼 누르기 — UIKit 인식기로 받음.
/// 화면 아래쪽은 iOS가 홈 바 제스처인지 보느라 화면(뷰)에 터치를 늦게 넘기는데, 인식기는 바로 받음
/// 짧게 = QR 찍기 · holdAfter 초 = 메뉴 · 누른 채 밀어서 떼면 그 항목
struct PressCatcher: UIViewRepresentable {
    var holdAfter: TimeInterval
    var onDown: () -> Void
    var onHold: () -> Void
    var onMove: (CGPoint) -> Void   // 윈도우 좌표 (= SwiftUI .global)
    var onUp: (Bool) -> Void        // 손가락이 많이 움직였는지
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let g = TimedPress(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        g.minimumPressDuration = 0
        g.allowableMovement = .greatestFiniteMagnitude
        g.cancelsTouchesInView = false
        g.delaysTouchesBegan = false
        v.addGestureRecognizer(g)
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: PressCatcher
        private var start: CGPoint = .zero
        private var moved = false
        private var timer: DispatchWorkItem?

        init(_ p: PressCatcher) { parent = p }

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            let loc = g.location(in: nil)
            switch g.state {
            case .began:
                #if DEBUG
                let down = (g as? TimedPress)?.downAt ?? ProcessInfo.processInfo.systemUptime
                print("O 버튼: 손댄 뒤 \(Int((ProcessInfo.processInfo.systemUptime - down) * 1000))ms 만에 터치 받음")
                #endif
                start = loc
                moved = false
                parent.onDown()
                timer?.cancel()
                let w = DispatchWorkItem { [weak self] in
                    guard let self, !self.moved else { return }
                    #if DEBUG
                    let down = (g as? TimedPress)?.downAt ?? 0
                    print("O 버튼: 손댄 뒤 \(Int((ProcessInfo.processInfo.systemUptime - down) * 1000))ms 만에 메뉴 띄움")
                    #endif
                    self.parent.onHold()
                }
                timer = w
                DispatchQueue.main.asyncAfter(deadline: .now() + parent.holdAfter, execute: w)
            case .changed:
                if hypot(loc.x - start.x, loc.y - start.y) > 24 { moved = true }   // 움직이면 길게 누르기 취소
                parent.onMove(loc)
            case .ended:
                timer?.cancel()
                parent.onUp(moved)
            case .cancelled, .failed:
                timer?.cancel()
                parent.onCancel()
            default:
                break
            }
        }
    }
}

/// 손가락이 실제로 닿은 시각을 기억하는 길게 누르기 인식기 (지연 확인용)
final class TimedPress: UILongPressGestureRecognizer {
    private(set) var downAt: TimeInterval = 0
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        downAt = touches.first?.timestamp ?? ProcessInfo.processInfo.systemUptime
        super.touchesBegan(touches, with: event)
    }
}
