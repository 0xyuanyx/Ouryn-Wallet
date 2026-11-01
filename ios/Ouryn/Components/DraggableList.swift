import SwiftUI

// src/components/DraggableList.js — 손잡이를 잡고 끌어서 순서 바꾸기

struct DraggableList<Row: View>: View {
    let ids: [String]
    var rowH: CGFloat = 72
    let onChange: ([String]) -> Void
    /// 끄는 동안 true — 바깥 스크롤을 잠깐 멈출 때
    var onDragging: ((Bool) -> Void)? = nil
    /// (id, 손잡이, 끌고 있는지)
    @ViewBuilder let render: (String, AnyView, Bool) -> Row

    @State private var order: [String] = []
    @State private var active: String? = nil
    @State private var dragY: CGFloat = 0
    @State private var startY: CGFloat = 0

    private var list: [String] { order.isEmpty ? ids : order }
    private let spring = Animation.spring(response: 0.32, dampingFraction: 0.78)

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(ids, id: \.self) { id in
                let isActive = active == id
                let idx = CGFloat(list.firstIndex(of: id) ?? 0)
                let y = isActive ? dragY : idx * rowH
                render(id, handle(id, isActive), isActive)
                    .frame(height: rowH)
                    .scaleEffect(isActive ? 1.02 : 1)
                    .offset(y: y)
                    .zIndex(isActive ? 10 : 1)
                    .animation(isActive ? nil : spring, value: y)
                    .animation(spring, value: isActive)
            }
        }
        .frame(height: CGFloat(list.count) * rowH, alignment: .top)
        .onAppear { order = ids }
        .onChange(of: ids) { _, v in
            // 바깥에서 순서가 바뀌면(기본 순서로 되돌리기 등) 맞춰서 이동
            if v != order { order = v }
        }
    }

    private func handle(_ id: String, _ isActive: Bool) -> AnyView {
        AnyView(
            Icon("reorder-three", 26, isActive ? C.text : C.mute)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                // 손잡이를 살짝(0.15초) 누르고 있어야 끌기 시작 → 손잡이 위를 쓸어도 스크롤은 그대로
                .gesture(
                    LongPressGesture(minimumDuration: 0.15, maximumDistance: 8)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { v in
                            if case .second(true, let drag) = v { move(id, drag?.translation.height ?? 0) }
                        }
                        .onEnded { _ in end(id) }
                )
                .accessibilityLabel("끌어서 순서 바꾸기")
        )
    }

    private func move(_ id: String, _ dy: CGFloat) {
        if active != id {
            if order.isEmpty { order = ids }
            startY = CGFloat(order.firstIndex(of: id) ?? 0) * rowH
            dragY = startY
            active = id
            onDragging?(true)
            haptic(.light)
        }
        let cur = order
        let y = min((CGFloat(cur.count) - 0.6) * rowH, max(-rowH * 0.4, startY + dy))
        dragY = y
        let to = Int(min(CGFloat(cur.count - 1), max(0, (y / rowH).rounded())))
        var rest = cur.filter { $0 != id }
        rest.insert(id, at: min(to, rest.count))
        if rest != cur {
            haptic(.select)
            order = rest
        }
    }

    private func end(_ id: String) {
        guard active != nil else { return }
        active = nil
        onDragging?(false)
        onChange(order)
    }
}
