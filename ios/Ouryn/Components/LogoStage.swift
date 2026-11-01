import SwiftUI

// src/components/LogoStage.js
// 로딩 → 완료를 한 화면에서. 로고 크기·위치 고정, 글자만 자리바꿈

struct LogoStage<Extra: View, Footer: View>: View {
    var done: Bool
    var loadingTitle: String
    var loadingSub: String? = nil
    var doneTitle: String
    var doneSub: String? = nil
    var size: CGFloat = 104
    @ViewBuilder var doneExtra: () -> Extra
    @ViewBuilder var footer: () -> Footer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var a: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in Color.clear.frame(maxHeight: .infinity) }
            LogoMark(status: done ? .done : .loading, size: size)
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    TX(loadingTitle, .sb, 18, align: .center)
                    if let s = loadingSub {
                        TX(s, .r, 14, C.mute, align: .center).padding(.top, 8)
                            .id(s)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .opacity(1 - a)
                VStack(spacing: 0) {
                    TX(doneTitle, .b, 24, lh: 34, align: .center)
                    if let s = doneSub {
                        TX(s, .r, 15, C.sub, lh: 22, align: .center).padding(.top, 8)
                    }
                    doneExtra()
                }
                .frame(maxWidth: .infinity)
                .opacity(a)
                .offset(y: reduceMotion ? 0 : 8 * (1 - a))
                .allowsHitTesting(done)
            }
            .padding(.horizontal, 24)
            .frame(height: 150, alignment: .top)
            .padding(.top, 28)
            ForEach(0..<5, id: \.self) { _ in Color.clear.frame(maxHeight: .infinity) }
            footer()
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .opacity(a)
                .allowsHitTesting(done)
        }
        .background(C.bg)
        .onAppear { if done { a = 1 } }
        .onChange(of: done) { _, d in
            // 로고가 완성되는 동안 글자를 기다리게 하던 시간을 줄임 (0.45 → 0.3초, 동작 줄이기면 바로)
            if d { withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Ease.standard(0.34).delay(0.3)) { a = 1 } }
        }
    }
}

extension LogoStage where Extra == EmptyView {
    init(done: Bool, loadingTitle: String, loadingSub: String? = nil, doneTitle: String, doneSub: String? = nil,
         size: CGFloat = 104, @ViewBuilder footer: @escaping () -> Footer) {
        self.init(done: done, loadingTitle: loadingTitle, loadingSub: loadingSub, doneTitle: doneTitle, doneSub: doneSub,
                  size: size, doneExtra: { EmptyView() }, footer: footer)
    }
}
