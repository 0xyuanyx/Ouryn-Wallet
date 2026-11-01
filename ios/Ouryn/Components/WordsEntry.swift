import SwiftUI

/// 12단어로 본인 확인 — Face ID 를 못 쓸 때 보내기 · 비밀번호를 잊었을 때
/// onSubmit 이 nil 을 돌려주면 통과, 문자열이면 그 이유를 보여줌
/// 입력한 단어는 Keychain 에 저장하지 않음 (확인·서명에만 쓰고 버림)
struct WordsEntry: View {
    let title: String
    let sub: String
    var button = "확인"
    let onCancel: () -> Void
    let onSubmit: (String) -> String?

    @State private var words = ""
    @State private var bad: String? = nil
    @Environment(\.scenePhase) private var phase

    private var list: [String] { WalletKeys.normalize(words).split(separator: " ").map(String.init) }

    var body: some View {
        let l = list
        let unknown = l.filter { !WalletKeys.isValidWord($0) }
        let countOk = l.count == 12 || l.count == 24
        VStack(alignment: .leading, spacing: 0) {
            Tap(action: { words = ""; onCancel() }) {
                Icon("close", 24, C.text).frame(width: 44, height: 44)
            }
            .padding(.leading, -12)
            .accessibilityLabel("닫기")
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TX(title, .b, 26, lh: 36).padding(.top, 10)
                    TX(sub, .r, 15, C.sub, lh: 22)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    Field(text: $words, placeholder: "apple banana …", mono: true).padding(.top, 24)
                    HStack {
                        TX("\(l.count)/12", .m, 13, countOk ? C.green : C.mute)
                        Spacer()
                        Tap(action: {
                            if let t = UIPasteboard.general.string {
                                words = WalletKeys.normalize(t); bad = nil
                                UIPasteboard.general.items = []   // 12단어가 클립보드에 남지 않게
                            }
                        }) {
                            TX("붙여넣기", .m, 13, C.sub).padding(.vertical, 6)
                        }
                    }
                    .padding(.top, 10)
                    if !unknown.isEmpty {
                        TX("목록에 없는 단어가 있어요: \(unknown.prefix(3).joined(separator: ", "))", .r, 13, C.red).padding(.top, 6)
                    } else if let bad {
                        TX(bad, .r, 13, C.red, lh: 19).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    }
                    Warn(text: "주변에 화면을 보는 사람이 없을 때만 입력하세요", compact: true).padding(.top, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            OButton(button, disabled: !countOk || !unknown.isEmpty) {
                let w = WalletKeys.normalize(words)
                guard WalletKeys.isValid(w) else {
                    bad = "단어는 맞는데 순서나 조합이 맞지 않아요. 적어둔 종이를 다시 확인해주세요."; haptic(.error); return
                }
                if let reason = onSubmit(w) { bad = reason; haptic(.error) }
                else { hideKeyboard(); words = "" }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(C.bg.ignoresSafeArea())
        // 앱 전환 화면에 입력한 단어가 남지 않게
        .overlay { if phase != .active { C.bg.ignoresSafeArea() } }
        .onDisappear { words = "" }
    }
}
