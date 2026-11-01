import SwiftUI
import Combine

// src/components/Toast.js + 잠금 화면을 앱 전체(모달 포함) 위에 띄우는 창

final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var text = ""
    @Published var icon = "checkmark-circle"
    @Published var a: Double = 0
    private var work: DispatchWorkItem?

    func show(_ text: String, _ icon: String = "checkmark-circle") {
        self.text = text
        self.icon = icon
        work?.cancel()
        withAnimation(.interpolatingSpring(stiffness: 240, damping: 18)) { a = 1 }
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) { self?.a = 0 }
        }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: w)
    }
}

func toast(_ text: String, _ icon: String = "checkmark-circle") {
    ToastCenter.shared.show(text, icon)
}

struct ToastOverlay: View {
    @ObservedObject var center = ToastCenter.shared

    var body: some View {
        VStack {
            Spacer()
            if !center.text.isEmpty {
                HStack(spacing: 8) {
                    Icon(center.icon, 18, center.icon == "checkmark-circle" ? C.green : C.sub)
                    TX(center.text, .m, 14)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16).fill(C.surface3))
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 6)
                .opacity(center.a)
                .offset(y: 20 * (1 - center.a))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .allowsHitTesting(false)
    }
}

/// 터치를 아래 창으로 그대로 흘려보내는 창
final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

final class Overlays {
    static let shared = Overlays()
    private var toastWindow: UIWindow?
    private var lockWindow: UIWindow?
    private var privacyWindow: UIWindow?
    private var bag = Set<AnyCancellable>()
    private weak var scene: UIWindowScene?

    func setup(scene: UIWindowScene, store: Store) {
        guard self.scene == nil else { return }
        self.scene = scene

        let tw = PassThroughWindow(windowScene: scene)
        tw.windowLevel = .normal + 2
        tw.backgroundColor = .clear
        tw.overrideUserInterfaceStyle = .dark
        let th = UIHostingController(rootView: ToastOverlay())
        th.view.backgroundColor = .clear
        tw.rootViewController = th
        tw.isHidden = false
        toastWindow = tw

        // 앱 전환 화면 가림막 — iOS 가 백그라운드로 갈 때 찍는 화면 사진에 12단어·잔액이 남지 않게
        // 모달·시트보다 위에 있는 별도 창이라 어떤 화면이든 가려짐. 미리 만들어 두고 보이기만 바꿈
        let pw = UIWindow(windowScene: scene)
        pw.windowLevel = .normal + 3
        pw.backgroundColor = UIColor(C.bg)
        pw.overrideUserInterfaceStyle = .dark
        let ph = UIHostingController(rootView: PrivacyCover())
        ph.view.backgroundColor = UIColor(C.bg)
        pw.rootViewController = ph
        pw.isHidden = true
        privacyWindow = pw
        let nc = NotificationCenter.default
        nc.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.privacyWindow?.isHidden = false }
            .store(in: &bag)
        nc.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.privacyWindow?.isHidden = true }
            .store(in: &bag)

        store.$locked
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.setLock(on, store: store) }
            .store(in: &bag)
    }

    private func setLock(_ on: Bool, store: Store) {
        if on {
            guard lockWindow == nil, let scene = scene else { return }
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .normal + 1
            w.backgroundColor = .clear
            w.overrideUserInterfaceStyle = .dark
            let host = UIHostingController(rootView: AnyView(LockView().environmentObject(store)))
            host.view.backgroundColor = .clear
            w.rootViewController = host
            w.isHidden = false
            lockWindow = w
        } else {
            lockWindow?.isHidden = true
            lockWindow = nil
        }
    }
}

/// 앱 전환 화면에 보이는 가림막
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            C.bg.ignoresSafeArea()
            Logo(size: 72)
        }
        .accessibilityHidden(true)
    }
}
