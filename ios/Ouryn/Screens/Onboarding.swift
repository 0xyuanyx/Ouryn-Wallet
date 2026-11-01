import SwiftUI
import LocalAuthentication

// 실제 지갑 만들기 / 되찾기
// 새 지갑:  welcome → intro → pin → pin2 → (bio) → making(키 생성) → done → show(12단어) → quiz → 끝
// 되찾기:   welcome → where → words(12단어) → pin → pin2 → (bio) → making → done → 끝
// 이 폰에 키가 남아 있으면(앱을 지웠다 다시 깔았을 때): welcome → oldpin(예전 비밀번호) → (bio) → making
//   예전 비밀번호를 잊었으면 12단어 입력 → 같은 지갑이면 reopen(새 비밀번호), 다른 지갑이면 바꾸기 경고
// 백업 없음: where → none (자기주권 설명)

struct OnboardingView: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = "welcome"
    @State private var mode = "new"        // new | restore | existing(예전 비밀번호로) | reopen(같은 12단어로)
    @State private var pin = ""
    @State private var words = ""
    @State private var wordsBad = false
    @State private var addrs: ChainAddrs? = nil
    @State private var useB = false
    @State private var bio = Bio.info()
    @State private var fade: Double = 1
    @State private var overwriteOpen = false
    @State private var replaceOpen = false
    @State private var quiz: [Int] = []    // 확인할 단어 위치 (0부터)
    @State private var quizOptions: [[String]] = []
    @State private var quizIndex = 0
    @State private var picked: String? = nil
    @State private var quizBad = false
    private var hasOld: Bool { store.hasSavedKey }

    private var phase: String { step == "done" ? "making" : step }
    private var back: String? {
        switch step {
        case "intro": return "welcome"
        case "where": return "welcome"
        case "words", "none": return hasOld ? "welcome" : "where"
        case "pin": return mode == "new" ? "intro" : (mode == "restore" || mode == "reopen" ? "words" : "welcome")
        case "oldpin": return "welcome"
        case "pin2": return "pin"
        case "quiz": return "show"
        default: return nil
        }
    }
    private var wordList: [String] { WalletKeys.normalize(words).split(separator: " ").map(String.init) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let b = back {
                    Tap(action: { step = b }) { Icon("chevron-back", 26, C.text).padding(12) }
                        .padding(-12)
                        .accessibilityLabel("뒤로")
                }
                Spacer()
            }
            // 12단어 화면은 뒤로 가기가 없어서 빈 헤더 자리를 없애고 위로 붙임
            .frame(height: step == "show" ? 0 : 52)
            .padding(.horizontal, 16)
            .padding(.top, step == "show" ? 0 : 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(fade)
                .offset(y: reduceMotion ? 0 : 12 * (1 - fade))
        }
        .background(C.bg.ignoresSafeArea())
        .onChange(of: phase) { _, _ in
            noAnim { fade = 0 }
            DispatchQueue.main.async { withAnimation(Ease.outCubic(reduceMotion ? 0.2 : 0.35)) { fade = 1 } }
        }
        .onChange(of: step) { _, s in
            if s == "making" { makeKeys() }
            if s == "quiz" { startQuiz() }
        }
        .oSheet($overwriteOpen, title: "이 폰에 이미 지갑이 있어요",
                sub: "새로 만들면 이 폰에 있던 지갑 열쇠는 지워져요. 그 지갑의 돈은 복구 문구로만 다시 꺼낼 수 있어요.") {
            VStack(spacing: 8) {
                OButton("이 폰에 있던 지갑 먼저 열기") { overwriteOpen = false; after(0.3) { openOld() } }
                HStack(spacing: 8) {
                    OButton("취소", kind: .secondary) { overwriteOpen = false }
                    OButton("그래도 새로 만들기", kind: .danger) { overwriteOpen = false; mode = "new"; step = "intro" }
                }
            }
        }
        .oSheet($replaceOpen, title: "이 폰에 다른 지갑이 있어요",
                sub: "입력한 12단어는 이 폰에 있던 지갑과 달라요. 바꾸면 이 폰에 있던 지갑 열쇠가 지워지고, 그 지갑의 돈은 그 지갑의 12단어로만 꺼낼 수 있어요.") {
            VStack(alignment: .leading, spacing: 8) {
                TX("그 지갑 12단어를 적어두지 않았다면 먼저 열어서 확인하세요. 입력한 지갑은 그다음 ‘지갑 추가’로 함께 쓸 수 있어요.",
                   .r, 13, C.sub, lh: 19)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
                OButton("이 폰에 있던 지갑 먼저 열기") { replaceOpen = false; words = ""; after(0.3) { openOld() } }
                HStack(spacing: 8) {
                    OButton("취소", kind: .secondary) { replaceOpen = false }
                    OButton("그래도 바꾸기", kind: .danger) { replaceOpen = false; mode = "restore"; step = "pin" }
                }
            }
        }
    }

    /// 이 폰에 남아 있던 지갑 열기 — 예전 비밀번호 확인 (앱을 다시 깔아도 비밀번호는 Keychain 에 남아 있음)
    private func openOld() {
        mode = "existing"
        if PinVault.exists { step = "oldpin"; return }
        // 비밀번호를 Keychain 에 두기 전 버전에서 만든 지갑: 폰 암호로라도 본인 확인
        let ctx = LAContext()
        ctx.localizedCancelTitle = "취소"
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "이 폰에 있던 지갑 열기") { ok, _ in
            DispatchQueue.main.async { if ok { step = "pin" } }
        }
    }

    // 키 만들기 / 되찾기 → 잠깐 로고 애니메이션 → done
    private func makeKeys() {
        let started = Date()
        let m = mode, w = words
        DispatchQueue.global(qos: .userInitiated).async {
            let result: ChainAddrs?
            switch m {
            case "restore": result = WalletKeys.restore(w)
            // 예전 비밀번호를 맞힘 → 12단어는 Face ID 로 꺼냄
            case "existing": result = WalletKeys.openExisting(reason: "이 폰에 있던 지갑 열기")
            // 같은 12단어를 입력함 → 입력한 단어로 다시 저장 (Face ID 가 바뀌었거나 고장 나도 열림)
            case "reopen": result = WalletKeys.restore(w)
            default: result = WalletKeys.create()
            }
            let wait = max(0, 1.6 - Date().timeIntervalSince(started))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                guard step == "making" else { return }
                if let r = result { addrs = r; step = "done" } else { haptic(.error); step = "error" }
            }
        }
    }

    private func finish(backedUp: Bool) {
        guard let a = addrs else { return }
        guard store.finishOnboarding(addrs: a, restored: mode == "restore" || mode == "reopen", pin: pin, bio: useB, backedUp: backedUp) else {
            haptic(.error)
            toast("비밀번호를 저장하지 못했어요. 다시 시도해주세요", "alert-circle")
            return
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case "welcome": welcome
        case "intro": intro
        case "where": whereStep
        case "words": wordsStep
        case "none": noneStep
        case "show": showStep
        case "quiz": quizStep
        case "error": errorStep
        case "pin":
            PinPad(title: "앱에서 쓸 간편 비밀번호", sub: "숫자 4자리를 입력해주세요", onComplete: { p in
                if let r = PinVault.weakReason(p) { return .message(r) }
                pin = p
                step = "pin2"
                return .ok
            }, header: { Logo(size: 48) })
            .id("pin")
        case "oldpin":
            PinPad(title: "이 폰에서 쓰던 간편 비밀번호", sub: "지갑을 열려면 예전 비밀번호가 필요해요", length: PinVault.length, onComplete: { p in
                let r = store.checkPin(p)
                guard case .ok = r else { return r }
                pin = p
                step = bio.ok ? "bio" : "making"
                return .ok
            }, header: { Logo(size: 48) }, footer: {
                Tap(action: { mode = "restore"; words = ""; wordsBad = false; step = "words" }) {
                    TX("비밀번호를 잊었어요 · 12단어로 열기", .m, 14, C.sub).underline(color: C.sub).padding(12)
                }
                .padding(.bottom, 8)
            })
            .id("oldpin")
        case "pin2":
            PinPad(title: "한 번 더 입력해주세요", sub: "확인을 위해 같은 숫자를 눌러주세요", onComplete: { p in
                if p != pin { return .message("처음 입력한 숫자와 달라요") }
                step = bio.ok ? "bio" : "making"
                return .ok
            }, header: { Logo(size: 48) })
            .id("pin2")
        case "bio": bioStep
        default:
            LogoStage(done: step == "done",
                      loadingTitle: mode == "new" ? "나만의 지갑을 만들고 있어요" : "지갑을 불러오고 있어요",
                      loadingSub: "열쇠는 이 폰 안에만 보관해요",
                      doneTitle: mode == "new" ? "지갑이 준비됐어요" : "다시 만나서 반가워요",
                      doneSub: mode == "new" ? "이제 복구 문구 12단어를 적어둘 차례예요.\n폰을 잃어버려도 이 단어로 되찾아요." : "이 지갑은 여전히\n온전히 당신의 것이에요.",
                      size: 112) {
                if mode == "new" {
                    OButton("복구 문구 적기") { step = "show" }
                } else {
                    OButton("내 지갑 보러가기") { finish(backedUp: false) }
                }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()
                Breathing { Logo(size: 120) }
                TX("내 돈의\n새로운 일상.", .b, 28, lh: 38, align: .center).padding(.top, 40)
                TX("은행 없이도, 내 돈은 온전히 내 것으로.", .r, 16, C.sub, lh: 24, align: .center).padding(.top, 14)
                Spacer()
            }
            VStack(spacing: 8) {
                if hasOld {
                    OButton("이 폰에 있던 지갑 열기") { openOld() }
                    OButton("새 지갑 만들기", kind: .secondary) { overwriteOpen = true }
                    OButton("복구 문구로 되찾기", kind: .ghost) { mode = "restore"; words = ""; wordsBad = false; step = "words" }
                } else {
                    OButton("시작하기") { mode = "new"; step = "intro" }
                    OButton("이미 쓰던 지갑이 있어요", kind: .ghost) { step = "where" }
                }
            }
        }
        .padding(24)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            TX("시작하기 전에\n이것만 알아두세요", .b, 26, lh: 36)
            VStack(alignment: .leading, spacing: 28) {
                Point(icon: "key", title: "내 돈은 나만 꺼낼 수 있어요", sub: "회사도, 누구도 대신 꺼내거나 막을 수 없어요.")
                Point(icon: "document-lock", title: "복구 문구 12단어가 유일한 백업이에요", sub: "지갑 열쇠는 이 폰 안에만 있어요. 폰을 잃어버리면 12단어로만 되찾을 수 있어요.")
                Point(icon: "globe", title: "실제 블록체인 지갑이에요", sub: "솔라나·이더리움·비트코인·카르다노 주소가 만들어지고, 잔액은 실제 네트워크에서 읽어요.")
            }
            .padding(.top, 36)
            Spacer()
            OButton("좋아요") { step = "pin" }
        }
        .padding(24)
    }

    // 되찾기 1: 어디에 보관했나요?
    private var whereStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            TX("쓰던 지갑을\n어떻게 되찾을까요?", .b, 26, lh: 36)
            TX("다른 지갑 앱(Phantom·MetaMask 등)에서 쓰던 영어 12단어도 그대로 쓸 수 있어요.", .r, 15, C.sub, lh: 22).padding(.top, 10)
            VStack(spacing: 10) {
                Choice(icon: "document-lock", title: "복구 문구 12단어", sub: "종이에 적어둔 영어 단어로 되찾기") {
                    mode = "restore"; words = ""; wordsBad = false; step = "words"
                }
                Choice(icon: "logo-apple", title: "iCloud", sub: "준비 중이에요", enabled: false) {}
                Choice(icon: "logo-google", title: "구글 드라이브", sub: "준비 중이에요", enabled: false) {}
            }
            .padding(.top, 28)
            Spacer()
            Tap(action: { step = "none" }) {
                TX("복구 문구가 없어요", .m, 15, C.sub).underline(color: C.sub).padding(12)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    // 되찾기 2: 12단어 입력
    private var wordsStep: some View {
        let list = wordList
        let unknown = list.filter { !WalletKeys.isValidWord($0) }
        let countOk = list.count == 12 || list.count == 24
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TX("복구 문구를\n순서대로 입력해주세요", .b, 26, lh: 36)
                    TX("영어 단어 사이는 띄어 써주세요. 입력한 단어는 이 폰 밖으로 나가지 않아요.", .r, 15, C.sub, lh: 22).padding(.top, 10)
                    Field(text: $words, placeholder: "apple banana …").padding(.top, 24)
                    HStack {
                        TX("\(list.count)/12", .m, 13, countOk ? C.green : C.mute)
                        Spacer()
                        Tap(action: {
                            if let t = UIPasteboard.general.string {
                                words = WalletKeys.normalize(t); wordsBad = false
                                UIPasteboard.general.items = []   // 12단어가 클립보드에 남지 않게
                            }
                        }) {
                            TX("붙여넣기", .m, 13, C.sub).padding(.vertical, 6)
                        }
                    }
                    .padding(.top, 10)
                    if !unknown.isEmpty {
                        TX("목록에 없는 단어가 있어요: \(unknown.prefix(3).joined(separator: ", "))", .r, 13, C.red).padding(.top, 6)
                    } else if wordsBad {
                        TX("단어는 맞는데 순서나 조합이 맞지 않아요. 적어둔 종이를 다시 확인해주세요.", .r, 13, C.red).padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            OButton("다음", disabled: !countOk || !unknown.isEmpty) {
                guard WalletKeys.isValid(words) else { wordsBad = true; haptic(.error); return }
                if !hasOld { mode = "restore"; step = "pin" }
                // 이 폰에 남은 지갑과 같은 12단어 = 주인 확인 → 덮어쓰지 않고 그대로 열고 새 비밀번호
                else if WalletKeys.holds(words, wallet: "main") { mode = "reopen"; step = "pin" }
                else { hideKeyboard(); replaceOpen = true }
            }
        }
        .padding(24)
    }

    // 복구 문구가 없을 때
    private var noneStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TX("복구 문구가 없다면", .b, 26, lh: 36)
                    TX("이것부터 확인해보세요", .m, 15, C.sub).padding(.top, 20)
                    Guide(items: [
                        "예전 폰이 아직 있다면, 그 폰의 Ouryn 전체 → 복구 문구 보기에서 12단어를 확인할 수 있어요",
                        "다른 지갑 앱을 쓰고 있었다면 그 앱의 ‘비밀 복구 문구’ 메뉴를 찾아보세요",
                        "종이·수첩·금고 등 적어둘 만한 곳을 다시 확인해보세요",
                    ])
                    Notice(icon: "key", color: C.sub, bg: C.surface, title: "복구 문구가 정말 없다면",
                           text: "그 지갑은 누구도 되찾을 수 없어요. 저희도요. 대신 그 지갑의 돈도 누구도 꺼낼 수 없어요. 내 돈을 나만 가진다는 건 이런 뜻이에요.")
                        .padding(.top, 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 8) {
                OButton("복구 문구 입력하기") { mode = "restore"; words = ""; wordsBad = false; step = "words" }
                OButton("새 지갑 만들기", kind: .ghost) {
                    if hasOld { overwriteOpen = true } else { mode = "new"; step = "intro" }
                }
            }
        }
        .padding(24)
    }

    // 새 지갑: 12단어 보여주기
    // 위: 제목 + 12단어 / 아래: 주의사항 + 버튼
    // 주의사항을 버튼 바로 위에 두면 누르기 전에 읽게 되고, 가운데 빈 공간도 생기지 않음
    private var showStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TX("12단어를 순서대로 적어주세요", .b, 24)
                    TX("이 단어가 지갑 그 자체예요. 폰을 잃어버려도 이 단어로 되찾아요.", .r, 14, C.sub, lh: 20)
                        .padding(.top, 8)
                    MnemonicGrid(words: WalletKeys.freshWords, compact: true).padding(.top, 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 52)
            }
            VStack(alignment: .leading, spacing: 6) {
                Warn(text: "누군가 이 단어를 알면 내 돈을 전부 가져갈 수 있어요", compact: true)
                Warn(text: "캡처·사진·메모 앱 말고 종이에 적어주세요", compact: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(C.redSoft))
            .padding(.top, 12)
            .padding(.bottom, 16)
            VStack(spacing: 8) {
                OButton("다 적었어요") { step = "quiz" }
                OButton("나중에 적을게요", kind: .ghost) { finish(backedUp: false) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    // 새 지갑: 제대로 적었는지 두 단어 확인
    private func startQuiz() {
        let all = WalletKeys.freshWords
        quiz = [12, 24].contains(all.count) ? Array(all.indices.shuffled().prefix(2)).sorted() : []
        quizOptions = quiz.map { QuizOptions.get($0, all) }
        quizIndex = 0
        picked = nil
        quizBad = false
    }

    private var quizStep: some View {
        let ready = quiz.count == 2 && quizOptions.count == 2
            && quizOptions.allSatisfy { $0.count == 6 } && quiz.indices.contains(quizIndex)
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TX("잘 적었는지\n확인해볼게요", .b, 26, lh: 36)
                    TX("적어둔 종이를 보고 골라주세요.", .r, 15, C.sub).padding(.top, 10)
                    if ready {
                        TX("확인 \(quizIndex + 1)/2", .m, 14, C.sub).padding(.top, 28)
                        TX("\(quiz[quizIndex] + 1)번째 단어", .sb, 18).padding(.top, 10)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(quizOptions[quizIndex], id: \.self) { word in
                                Tap(action: { picked = word; quizBad = false }) {
                                    TX(word, .sb, 16)
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(C.surface2))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(picked == word ? C.text : C.line, lineWidth: 1)
                                        }
                                }
                                .accessibilityAddTraits(picked == word ? [.isSelected] : [])
                            }
                        }
                        .padding(.top, 16)
                    } else {
                        TX("확인 문제를 준비하지 못했어요. 뒤로 가서 다시 시도해주세요.", .r, 15, C.red)
                            .padding(.top, 28)
                    }
                    if quizBad {
                        TX("맞지 않는 단어예요. 적어둔 종이를 다시 확인해주세요.", .r, 13, C.red).padding(.top, 16)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            OButton(quizIndex == 0 ? "확인하고 다음으로" : "확인", disabled: !ready || picked == nil) {
                guard ready else { return }
                let all = WalletKeys.freshWords
                let position = quiz[quizIndex]
                guard all.indices.contains(position), picked == all[position] else {
                    haptic(.error); quizBad = true; return
                }
                if quizIndex == 0 {
                    quizIndex = 1; picked = nil; quizBad = false
                } else {
                    haptic(.success); finish(backedUp: true)
                }
            }
            .padding(.top, 16)
        }
        .padding(24)
    }

    private var errorStep: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack { Circle().fill(C.redSoft); Icon("alert-circle", 44, C.red) }.frame(width: 96, height: 96)
            TX("지갑을 준비하지 못했어요", .b, 22, align: .center).padding(.top, 24)
            TX("이 폰의 보안 저장소(키체인)를 열지 못했어요.\n폰 잠금(암호)과 Face ID가 켜져 있는지 확인하고 다시 해주세요.", .r, 15, C.sub, lh: 22, align: .center)
                .padding(.top, 10)
            Spacer()
            OButton("다시 하기") { step = "making" }
        }
        .padding(24)
    }

    private var bioStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 30).fill(C.surface)
                    Icon(bio.icon, 52, C.text)
                }
                .frame(width: 96, height: 96)
                TX("\(bio.label)으로\n더 빠르게 열까요?", .b, 24, lh: 34, align: .center).padding(.top, 28)
                TX("비밀번호 대신 쓸 수 있어요. 언제든 끌 수 있어요.", .r, 15, C.sub, align: .center).padding(.top, 10)
                Spacer()
            }
            VStack(spacing: 8) {
                OButton("\(bio.label) 쓰기") {
                    Bio.auth("등록 확인") { ok in
                        if ok { useB = true; step = "making" }
                    }
                }
                OButton("나중에 할게요", kind: .ghost) { step = "making" }
            }
        }
        .padding(24)
    }
}

private struct Choice: View {
    let icon: String
    let title: String
    let sub: String
    var enabled = true
    let onPress: () -> Void

    var body: some View {
        Tap(scale: 0.98, haptics: .select, disabled: !enabled, action: onPress) {
            HStack(spacing: 14) {
                ZStack { RoundedRectangle(cornerRadius: 12).fill(C.surface2); Icon(icon, 20, C.text) }
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    TX(title, .sb, 16)
                    TX(sub, .r, 13, C.mute)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon("chevron-forward", 18, C.faint)
            }
            .padding(14)
            .edge(18, C.surface)
            .opacity(enabled ? 1 : 0.5)
        }
    }
}

private struct Point: View {
    let icon: String
    let title: String
    let sub: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(C.surface)
                Icon(icon, 22, C.text)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 0) {
                TX(title, .sb, 17)
                TX(sub, .r, 14, C.sub, lh: 20).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct Check: View {
    let ok: Bool
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Icon("checkmark-circle", 16, ok ? C.green : C.faint)
            TX(label, .r, 13, ok ? C.sub : C.mute)
        }
    }
}

// 숨 쉬듯 살짝 커졌다 작아짐
struct Breathing<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        content()
            .scaleEffect(on ? 1.05 : 1)
            .onAppear {
                if reduceMotion { return }
                withAnimation(Ease.inOutSin(1.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// 튀어나오며 나타남
struct Pop<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var a: CGFloat = 0

    var body: some View {
        content()
            .opacity(Double(a))
            .scaleEffect(a)
            .onAppear {
                if reduceMotion { a = 1 } else { withAnimation(Ease.rnSpring(friction: 5, tension: 120)) { a = 1 } }
            }
    }
}
