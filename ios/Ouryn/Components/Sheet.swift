import SwiftUI

// src/components/Sheet.js — 아래에서 올라오는 시트 (배경 어둡게 + 스프링)
// 화면 전체(헤더·탭 포함)를 덮도록 투명한 fullScreenCover 위에 그림

struct SheetPanel<Content: View>: View {
    @Binding var isPresented: Bool
    var title: String?
    var sub: String?
    let onGone: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var a: CGFloat = 0
    @GestureState private var dragY: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.6 * a)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Capsule().fill(C.surface3).frame(width: 40, height: 5)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                            .padding(.bottom, 20)
                        if let t = title {
                            TX(t, .b, 21).padding(.bottom, sub != nil ? 8 : 18)
                        }
                        if let s = sub {
                            TX(s, .r, 15, C.sub, lh: 22).padding(.bottom, 20)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .updating($dragY) { value, state, _ in state = max(0, value.translation.height) }
                            .onEnded { value in
                                if value.translation.height > 80 || value.predictedEndTranslation.height > 160 {
                                    isPresented = false
                                }
                            }
                    )
                    .accessibilityAction(.escape) { isPresented = false }
                    content()
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                        .fill(C.sheet)
                        .ignoresSafeArea(edges: .bottom)
                )
                .offset(y: (1 - a) * (geo.size.height + geo.safeAreaInsets.bottom) + dragY)
                .animation(.easeOut(duration: 0.2), value: dragY == 0)
            }
        }
        .onAppear {
            withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 220, damping: 22)) { a = 1 }
        }
        .onChange(of: isPresented) { _, v in
            if !v {
                withAnimation(.easeInOut(duration: 0.2)) { a = 0 } completion: { onGone() }
            }
        }
    }
}

struct OSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var title: String?
    var sub: String?
    @ViewBuilder var sheetContent: () -> SheetContent

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onAppear { if isPresented { noAnim { shown = true } } }
            .onChange(of: isPresented) { _, v in if v { noAnim { shown = true } } }
            .fullScreenCover(isPresented: $shown) {
                SheetPanel(isPresented: $isPresented, title: title, sub: sub, onGone: { noAnim { shown = false } }, content: sheetContent)
                    .presentationBackground(.clear)
            }
    }
}

extension View {
    func oSheet<C: View>(_ isPresented: Binding<Bool>, title: String? = nil, sub: String? = nil,
                         @ViewBuilder content: @escaping () -> C) -> some View {
        modifier(OSheetModifier(isPresented: isPresented, title: title, sub: sub, sheetContent: content))
    }
}
