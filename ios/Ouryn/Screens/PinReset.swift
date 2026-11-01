import SwiftUI

/// 비밀번호를 잊었을 때 — 본인 확인 → 새 4자리
/// - Face ID: 등록이 그대로일 때만 (등록이 바뀌었으면 남의 얼굴일 수 있어서 12단어만)
///   인증에 쓴 등록 상태를 그 자리에서 다시 비교 (화면을 띄워 둔 사이 새로 등록해도 통과 못 함)
/// - 12단어: 이 폰에 있는 지갑 중 하나와 맞으면 (Keychain 을 읽지 않고 지문·주소로 비교)
/// 두 방법 모두 10번 실패 잠금(hardLocked)도 풂 — 비밀번호 추측이 아닌 다른 본인 확인이라서
/// 앱을 지우고 다시 깔지 않아도 돼서 내역·주소록이 그대로 남음
struct PinResetView: View {
    @EnvironmentObject var store: Store
    /// true = 새 비밀번호를 정함
    let done: (Bool) -> Void

    @State private var step = "choose"   // choose | words | new | again
    @State private var next = ""
    @State private var bio = Bio.info()
    @State private var bioChanged = Biometry.changed()

    private var faceOk: Bool { bio.ok && !bioChanged }

    var body: some View {
        Group {
            switch step {
            case "words":
                WordsEntry(title: "12단어로 확인할게요",
                           sub: "이 폰에 있는 지갑의 12단어를 입력하면 비밀번호를 새로 정할 수 있어요. 입력한 단어는 저장하지 않아요.",
                           onCancel: { step = "choose" }) { w in
                    guard store.wordsMatchAnyWallet(w) else {
                        return "이 폰에 있는 지갑의 12단어가 아니에요. 적어둔 종이를 다시 확인해주세요."
                    }
                    // 12단어 = 가장 확실한 본인 확인 → 잠금을 풀고 지금 Face ID 등록을 기준으로
                    PinVault.clearHardLock()
                    Biometry.accept()
                    step = "new"
                    return nil
                }
            case "new":
                PinPad(title: "새 비밀번호", sub: "숫자 4자리를 입력해주세요", onComplete: { p in
                    if let r = PinVault.weakReason(p) { return .message(r) }
                    next = p
                    step = "again"
                    return .ok
                }, footer: { cancel })
                .id("new")
            case "again":
                PinPad(title: "한 번 더 입력해주세요", onComplete: { p in
                    if p != next { return .message("새 비밀번호와 달라요") }
                    guard store.setPin(p) else { return .message("비밀번호를 저장하지 못했어요. 다시 시도해주세요") }
                    haptic(.success)
                    toast("비밀번호를 새로 정했어요")
                    done(true)
                    return .ok
                }, footer: { cancel })
                .id("again")
            default:
                choose
            }
        }
        .background(C.bg.ignoresSafeArea())
        .onAppear { bio = Bio.info(); bioChanged = Biometry.changed() }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 0) {
            Tap(action: { done(false) }) {
                Icon("close", 24, C.text).frame(width: 44, height: 44)
            }
            .padding(.leading, -12)
            .accessibilityLabel("닫기")
            TX("비밀번호를\n새로 정할게요", .b, 26, lh: 36).padding(.top, 10)
            TX(faceOk ? "\(bio.label)이나 12단어로 본인 확인을 하면 새 비밀번호를 정할 수 있어요."
               : bio.ok ? "\(bio.label) 등록이 바뀌어서 지금은 12단어로만 확인할 수 있어요."
               : "12단어로 본인 확인을 하면 새 비밀번호를 정할 수 있어요.",
               .r, 15, C.sub, lh: 22)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Spacer()
            VStack(spacing: 8) {
                if faceOk {
                    OButton("\(bio.label)으로 확인") {
                        // 생체인증만 (아이폰 암호로 넘어가지 않음)
                        Bio.authTrusted("비밀번호 다시 정하기") { ok in
                            if ok { PinVault.clearHardLock(); step = "new" } else { bioChanged = Biometry.changed() }
                        }
                    }
                }
                OButton("12단어로 확인", kind: faceOk ? .secondary : .primary) { step = "words" }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var cancel: some View {
        Tap(action: { done(false) }) {
            TX("취소", .m, 15, C.sub).padding(12)
        }
        .padding(.bottom, 8)
    }
}
