import SwiftUI

// src/screens/Lock.js
// 비밀번호가 맞으면: 로고 한 바퀴 → 홈 로고 자리로 이동하며 작아짐 → 잠금 화면 사라짐

private let FROM: CGFloat = 56 // 잠금 화면 로고 크기
private let TO: CGFloat = 26 * LOGO_IN_CIRCLE // 홈 상단 통장 칩 안 로고 크기 (칩 왼쪽 16 + 6 + 13 = 중심 35)

struct LockView: View {
    @EnvironmentObject var store: Store
    @State private var bio = Bio.info()
    @State private var logoFrame: CGRect = .zero
    @State private var fly: CGPoint? = nil // 잠금 화면 로고의 시작 중심 (화면 좌표)
    @State private var spin: Double = 0
    @State private var move: CGFloat = 0
    @State private var pinFade: Double = 1
    @State private var bgFade: Double = 1
    @State private var resetting = false
    /// Face ID 등록이 바뀌었으면 Face ID 로 열지 않고 비밀번호를 한 번 받음 (맞으면 새 등록을 받아들임)
    @State private var bioChanged = Biometry.changed()

    var body: some View {
        GeometryReader { root in
            // 홈 상단 통장 칩 안 로고 위치 (Home: 위 여백 8, 높이 52, 칩 왼쪽 16 + 안쪽 6 + 반지름 13)
            let top: CGFloat = root.safeAreaInsets.top
            let target = CGPoint(x: CGFloat(35), y: top + CGFloat(34))   // 8 + 52/2
            ZStack {
                C.bg.opacity(bgFade).ignoresSafeArea()
                PinPad(title: "간편 비밀번호를 입력해주세요",
                       sub: bioChanged && store.st.bio ? "\(bio.label) 등록이 바뀌어서 비밀번호로 열어주세요" : nil,
                       length: PinVault.length,
                       onComplete: { p in
                           let r = store.checkPin(p)
                           guard case .ok = r else { return r }
                           unlock()
                           return .ok
                       },
                       header: {
                           Logo(size: FROM)
                               .opacity(fly == nil ? 1 : 0)
                               .background(
                                   GeometryReader { g in
                                       Color.clear
                                           .onAppear { logoFrame = g.frame(in: .global) }
                                           .onChange(of: g.frame(in: .global)) { _, f in logoFrame = f }
                                   }
                               )
                       },
                       footer: {
                           VStack(spacing: 0) {
                               if store.st.bio && bio.ok && !bioChanged {
                                   BioButton(label: bio.label, icon: bio.icon) { tryBio() }
                               }
                               Tap(action: { resetting = true }) {
                                   TX("비밀번호를 잊었어요", .m, 14, C.sub).underline(color: C.sub).padding(10)
                               }
                               .padding(.bottom, 4)
                           }
                       })
                    .opacity(pinFade)

                if let f = fly {
                    ZStack {
                        Logo(size: FROM)
                            .rotationEffect(.degrees(360 * spin))
                            .scaleEffect(1 + (TO / FROM - 1) * move)
                            .position(x: f.x + (target.x - f.x) * move, y: f.y + (target.y - f.y) * move)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                }
            }
        }
        .allowsHitTesting(fly == nil)
        .onAppear {
            bioChanged = Biometry.changed()
            if store.st.bio && bio.ok && !bioChanged { after(0.3) { tryBio() } }
        }
        .fullScreenCover(isPresented: $resetting) {
            PinResetView { ok in
                resetting = false
                if ok { after(0.35) { unlock() } }
            }
            .environmentObject(store)
        }
    }

    private func tryBio() {
        // 얼굴 등록이 그대로일 때만 연다. 화면을 띄워 둔 사이 새로 등록했으면 비밀번호로
        Bio.authTrusted("앱 열기") { ok in
            if ok { unlock() } else { bioChanged = Biometry.changed() }
        }
    }

    private func unlock() {
        guard fly == nil else { return }
        haptic(.success)
        fly = CGPoint(x: logoFrame.midX, y: logoFrame.midY)
        store.unlocking = true
        withAnimation(Ease.standard(0.22)) { pinFade = 0 }
        withAnimation(Ease.inOutCubic(0.56)) {
            spin = 1
        } completion: {
            withAnimation(Ease.standard(0.42).delay(0.12)) { bgFade = 0 }
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.52)) {
                move = 1
            } completion: {
                store.locked = false
                store.unlocking = false
            }
        }
    }
}

struct BioButton: View {
    let label: String
    let icon: String
    let onPress: () -> Void

    var body: some View {
        Tap(action: onPress) {
            HStack(spacing: 6) {
                Icon(icon, 18, C.text)
                TX("\(label)으로 열기", .m, 14)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Capsule().fill(C.surface))
        }
        .padding(.bottom, 12)
    }
}

/// 지우기처럼 되돌릴 수 없는 일 앞에서 간편 비밀번호 한 번 더 (얼굴 인식으로 대신하지 않음)
/// strict: 10번 넘게 틀린 뒤에는(hardLocked) 맞힌 비밀번호도 받지 않음 → '비밀번호를 잊었어요'로 본인 확인부터
struct PinGate: View {
    @EnvironmentObject var store: Store
    let title: String
    var sub: String? = nil
    var strict = false
    let done: (Bool) -> Void

    var body: some View {
        PinPad(title: title, sub: sub, length: PinVault.length,
               onComplete: { p in
                   let r = store.checkPin(p)
                   if case .ok = r {
                       if strict && PinVault.hardLocked {
                           return .message("비밀번호를 여러 번 틀려서 지금은 할 수 없어요. 잠금 화면의 '비밀번호를 잊었어요'로 다시 정해주세요")
                       }
                       haptic(.success); done(true)
                   }
                   return r
               },
               header: { Logo(size: 48) },
               footer: {
                   Tap(action: { done(false) }) {
                       TX("취소", .m, 15, C.sub).padding(12)
                   }
                   .padding(.bottom, 8)
               })
            .background(C.bg.ignoresSafeArea())
    }
}
