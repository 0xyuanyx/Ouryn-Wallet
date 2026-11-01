import SwiftUI

// src/components/Keypad.js + PinPad.js

struct KeyStyle: ButtonStyle {
    var enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 16).fill(configuration.isPressed && enabled ? C.surface : Color.clear))
            .contentShape(Rectangle())
    }
}

/// extra: "." | "00" | nil
struct Keypad: View {
    var extra: String? = nil
    let onKey: (String) -> Void

    var body: some View {
        let keys: [String?] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", extra, "0", "del"]
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { col in
                        let k = keys[row * 3 + col]
                        Button {
                            guard let k = k else { return }
                            haptic(.select)
                            onKey(k)
                        } label: {
                            if k == "del" {
                                Icon("backspace-outline", 26, C.text)
                            } else {
                                TX(k ?? "", .m, 26)
                            }
                        }
                        .buttonStyle(KeyStyle(enabled: k != nil))
                        .disabled(k == nil)
                        .accessibilityLabel(k == "del" ? "지우기" : (k ?? ""))
                        .accessibilityHidden(k == nil)
                    }
                }
            }
        }
    }
}

/// onComplete 결과
enum PinCheck {
    case ok
    case wrong // "비밀번호가 맞지 않아요"
    case message(String)
}

// 간편 비밀번호 입력 (새로 정할 때 4자리 · 확인할 때는 PinVault.length). onComplete 가 wrong/message 를 돌려주면 흔들고 지움
struct PinPad<Header: View, Footer: View>: View {
    var title: String
    var sub: String? = nil
    var error: String? = nil
    var length: Int = PinVault.newLength
    let onComplete: (String) -> PinCheck
    @ViewBuilder var header: () -> Header
    @ViewBuilder var footer: () -> Footer

    @State private var pin = ""
    @State private var err: String? = nil
    @State private var shake: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // 제목·점을 키패드 바로 위로 모아서 엄지 가까이에 둠. 위쪽 빈 공간은 로고 자리
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                header().padding(.bottom, Header.self == EmptyView.self ? 0 : 32)
                TX(title, .b, 22, align: .center)
                TX(err ?? sub ?? " ", .r, 15, err != nil ? C.red : C.sub, align: .center)
                    .frame(minHeight: 20)
                    .padding(.top, 10)
                HStack(spacing: 16) {
                    ForEach(0..<length, id: \.self) { i in
                        Circle().fill(i < pin.count ? C.text : C.surface3).frame(width: 14, height: 14)
                    }
                }
                .padding(.top, 28)
                .offset(x: shake)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(length)자리 중 \(pin.count)자리 입력함")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)

            VStack(spacing: 0) {
                footer()
                Keypad(onKey: onKey)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear { err = error }
        .onChange(of: error) { _, e in err = e }
    }

    private func doShake() {
        haptic(.error)
        let seq: [CGFloat] = [10, -10, 8, -8, 4, 0]
        for (i, v) in seq.enumerated() {
            after(Double(i) * 0.05) { withAnimation(.linear(duration: 0.05)) { shake = v } }
        }
    }

    private func onKey(_ k: String) {
        if k == "del" { if !pin.isEmpty { pin.removeLast() }; return }
        if pin.count >= length { return }
        let next = pin + k
        pin = next
        if next.count == length {
            after(0.12) {
                let res = onComplete(next)
                switch res {
                case .ok: break
                case .wrong:
                    err = "비밀번호가 맞지 않아요"
                    doShake()
                case .message(let m):
                    err = m
                    doShake()
                }
                // VoiceOver 사용자도 틀린 이유를 바로 듣게
                if case .ok = res {} else if let e = err { UIAccessibility.post(notification: .announcement, argument: e) }
                pin = ""
            }
        }
    }
}

extension PinPad where Header == EmptyView, Footer == EmptyView {
    init(title: String, sub: String? = nil, error: String? = nil, length: Int = PinVault.newLength,
         onComplete: @escaping (String) -> PinCheck) {
        self.init(title: title, sub: sub, error: error, length: length, onComplete: onComplete, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension PinPad where Header == EmptyView {
    init(title: String, sub: String? = nil, error: String? = nil, length: Int = PinVault.newLength,
         onComplete: @escaping (String) -> PinCheck, @ViewBuilder footer: @escaping () -> Footer) {
        self.init(title: title, sub: sub, error: error, length: length, onComplete: onComplete, header: { EmptyView() }, footer: footer)
    }
}

extension PinPad where Footer == EmptyView {
    init(title: String, sub: String? = nil, error: String? = nil, length: Int = PinVault.newLength,
         onComplete: @escaping (String) -> PinCheck, @ViewBuilder header: @escaping () -> Header) {
        self.init(title: title, sub: sub, error: error, length: length, onComplete: onComplete, header: header, footer: { EmptyView() })
    }
}
