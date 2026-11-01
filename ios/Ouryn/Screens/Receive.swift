import SwiftUI
import PhotosUI
import AVFoundation

// src/screens/Receive.js, Scan.js, Nearby.js

// MARK: - 받기 전 백업 확인

/// 12단어를 안 적은 진짜 지갑으로 돈을 받기 전에 한 번 막고 알려줌
/// 테스트 통장은 실제 돈이 아니라 제외. '위험을 알고 계속'을 고르면 그 화면을 닫을 때까지 다시 묻지 않음
struct BackupFirstGate: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    let onContinue: () -> Void

    /// 지금 통장이 진짜 통장이고, 그 지갑의 12단어를 아직 확인하지 않았는지
    static func needed(_ st: AppState) -> Bool { !st.inTest && !st.walletBackedUp(st.currentWallet?.id ?? "main") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack { RoundedRectangle(cornerRadius: 18).fill(C.redSoft); Icon("warning", 28, C.red) }
                        .frame(width: 56, height: 56)
                    TX("받기 전에\n12단어를 먼저 적어주세요", .b, 26, lh: 36).padding(.top, 20)
                    TX("이 지갑의 12단어를 아직 적지 않았어요. 폰이 고장 나거나 초기화되면, 이 주소로 받은 돈은 12단어 없이는 누구도 다시 꺼낼 수 없어요.",
                       .r, 15, C.sub, lh: 22)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    TX("앱을 지웠다 다시 깔거나 폰을 바꿀 때도 12단어가 필요해요. 종이에 적고 두 단어 확인까지 마치면 이 안내는 다시 나오지 않아요.",
                       .r, 15, C.sub, lh: 22)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            OButton("12단어 먼저 적기") {
                dismiss()
                after(0.4) { router.push(.recovery) }
            }
            OButton("위험을 알고 주소 보기", kind: .ghost, action: onContinue).padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

// MARK: - 받기

struct ReceiveView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// 1) 코인 → 2) 네트워크 → 3) 주소·QR
    @State private var showQR = false
    @State private var pickToken: String? = nil
    @State private var network = WalletNetwork.solana
    @State private var asset = "usdc"

    @State private var req: Double = 0
    @State private var open = false
    @State private var draft: Double = 0
    @State private var sharing = false
    @State private var riskOK = false   // 12단어를 안 적은 지갑인 걸 알고 주소를 보기로 함

    private var addr: String { store.st.address(net: network.rawValue) ?? "" }
    /// 금액 요청은 솔라나 달러만 (표준 Solana Pay 형식 → Phantom 등 다른 솔라나 지갑도 금액까지 읽음)
    private var canRequest: Bool { !Testnet.on && network == .solana && ["usdc", "usdt"].contains(asset) }
    /// 금액을 넣은 요청 QR 인지 — 내용이 길어서 원형 대신 네모 표준 QR 로 그림 (점이 작아져도 잘 읽히게)
    private var amountQR: Bool { canRequest && req > 0 }
    /// QR 내용 — 솔라나는 "solana:<주소>" (금액이 있으면 표준 Solana Pay), 나머지는 주소 그대로 (어느 지갑이든 읽음)
    /// 테스트 통장은 테스트넷 표시가 들어간 Ouryn 형식 → 찍는 쪽에서 테스트 통장으로만 보내게
    private var qrValue: String {
        if Testnet.on { return Testnet.payload(to: addr, network: network) }
        if amountQR { return payURI(to: addr, usd: req, asset: asset) }
        return network == .solana ? "solana:\(addr)" : addr
    }
    private var netName: String { Testnet.on ? Testnet.name(network) : "\(network.rawValue) 네트워크" }
    /// 공유 링크 — 금액이 있으면 표준 Solana Pay
    private var shareURI: String { canRequest && req > 0 ? payURI(to: addr, usd: req, asset: asset) : addr }

    private func copy() {
        guard !addr.isEmpty else { return }
        UIPasteboard.general.string = addr
        haptic(.success)
        toast("지갑 주소를 복사했어요")
    }

    private var shareText: String {
        if req > 0 {
            return "\(asset.uppercased())로 \(wonOf(req))(\(dollar(req)))을 보내주세요 · \(network.rawValue) 네트워크\n\(shareURI)"
        }
        return "여기로 보내주세요 · \(network.rawValue) 네트워크 \(asset.uppercased())\n\(addr)"
    }

    /// 코인 상세에서 '받기' → 그 코인으로 바로. 네트워크가 하나뿐이면 QR 까지
    private func openAsset() {
        guard let a = router.receiveAsset else { return }
        router.receiveAsset = nil
        let t = TokenCatalog.token(of: a)
        pickToken = t
        let items = TokenCatalog.choices.first(where: { $0.token == t })?.items ?? []
        if items.count == 1 {
            network = items[0].network
            asset = items[0].asset
            req = 0
            showQR = true
        }
    }

    private func back() {
        if showQR { showQR = false; if TokenCatalog.choices.first(where: { $0.token == pickToken })?.items.count ?? 0 < 2 { pickToken = nil } }
        else if pickToken != nil { pickToken = nil }
        else { dismiss() }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Tap(action: back) { Icon(showQR || pickToken != nil ? "chevron-back" : "close", 26, C.text).padding(16) }
                    .padding(-12)
                    .accessibilityLabel(showQR || pickToken != nil ? "뒤로" : "닫기")
                Spacer()
            }
            .frame(height: 52)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if showQR {
                Group {
                    if BackupFirstGate.needed(store.st) && !riskOK {
                        BackupFirstGate { riskOK = true }
                    } else {
                        qrStep
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ScrollView(showsIndicators: false) {
                    TokenNetworkPicker(
                        token: $pickToken,
                        title: "무엇을 받을까요?",
                        sub: "코인과 네트워크를 고르면 내 주소와 QR이 나와요",
                        networkTitle: "어느 네트워크로 받을까요?",
                        networkSub: "보내는 곳(거래소·지갑)에서 고른 네트워크와 같아야 해요. 다르면 돈을 돌려받기 어려워요.",
                        current: nil,
                        addressOf: { store.st.address(net: $0.rawValue) },
                        showBack: false
                    ) { it in
                        pickToken = TokenCatalog.token(of: it.asset)
                        network = it.network
                        asset = it.asset
                        req = 0
                        showQR = true
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    if pickToken == nil {
                        Tap(action: { router.present(.fromExchange(asset: nil)) }) {
                            HStack(spacing: 14) {
                                ZStack { Circle().fill(C.surface3); Icon("download-outline", 20, C.text) }
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 0) {
                                    TX("거래소에서 산 돈 가져오기", .sb, 15)
                                    TX("처음이어도 차근차근 알려드려요", .r, 13, C.mute).padding(.top, 3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Icon("chevron-forward", 18, C.faint)
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 18).fill(C.surface2))
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    }
                    Spacer().frame(height: 24)
                }
            }
        }
        .animation(ScanMotion.ease(0.25), value: showQR)
        .animation(ScanMotion.ease(0.2), value: pickToken)
        .onAppear(perform: openAsset)
        .background(C.bg.ignoresSafeArea())
        .oSheet($open, title: "얼마를 받을까요?", sub: "\(asset.uppercased())로 요청해요") {
            AmountEntry(receiving: true) { v, _ in draft = v }
                .frame(height: min(440, max(380, UIScreen.main.bounds.height - 260)))
                .padding(.horizontal, -22)
            OButton("이 금액으로 요청하기", disabled: !(draft > 0)) {
                req = (draft * 100).rounded() / 100 // 센트 단위로 맞춰야 보내는 쪽과 금액이 같게 보임
                open = false
                haptic(.success)
            }
        }
        .sheet(isPresented: $sharing) {
            ShareSheet(items: AddressQR.shareItems(payload: shareURI, label: "\(network.rawValue) · \(asset.uppercased())", text: shareText))
                .presentationDetents([.medium, .large])
        }
    }

    private var qrStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                TX("\(TokenCatalog.label(TokenCatalog.token(of: asset)).symbol) 받기", .b, 26)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TX(req > 0 ? "보내는 분이 이 QR을 찍으면 금액까지 채워져요" : "보내는 분에게 이 QR을 보여주세요",
                   .r, 15, C.sub).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)

                // 무엇을 · 어느 네트워크 (누르면 다시 고르기)
                Tap(action: { showQR = false; pickToken = nil }) {
                    HStack(spacing: 10) {
                        CoinLogo(asset: asset, network: network.rawValue, size: 30, ring: C.surface)
                        VStack(alignment: .leading, spacing: 1) {
                            TX(asset.uppercased(), .b, 15)
                            TX(netName, .r, 12, C.sub)
                        }
                        Spacer(minLength: 0)
                        TX("바꾸기", .m, 13, C.sub)
                        Icon("chevron-forward", 14, C.sub)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
                }
                .padding(.top, 20)

                if addr.isEmpty {
                    Notice(icon: "alert-circle", color: C.red, bg: C.redSoft, title: "주소를 보여드릴 수 없어요",
                           text: "주소 계산 자체 검사를 통과하지 못했어요. 잘못된 주소로 돈이 가지 않도록 막아뒀어요. 앱을 업데이트해주세요.")
                        .padding(.top, 28)
                } else if amountQR {
                    // 금액 요청: 표준 Solana Pay → 다른 솔라나 지갑으로 찍어도 받는 주소·코인·금액이 채워짐
                    AddressQRView(payload: qrValue)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
                        .padding(.top, 28)
                        .accessibilityLabel("금액 요청 QR")
                    TX("Phantom 등 다른 솔라나 지갑으로 찍어도 금액까지 채워져요", .r, 13, C.mute, align: .center)
                        .padding(.top, 10)
                } else {
                    RoundQR(value: qrValue, size: 250)
                        .padding(18)
                        .background(Circle().fill(C.surface))
                        .padding(.top, 28)
                    if Testnet.on { TestnetChip(text: "테스트넷 QR · 실제 돈 아님").padding(.top, 14) }
                }

                if req > 0 {
                    HStack(spacing: 8) {
                        TX("\(asset.uppercased()) \(wonOf(req)) 요청 중", .sb, 15, C.blueText)
                        Button { req = 0 } label: { Icon("close-circle", 18, C.blueText) }.buttonStyle(.plain)
                            .accessibilityLabel("요청 지우기")
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .frame(height: 36)
                    .background(Capsule().fill(C.blueSoft))
                    .padding(.top, 20)
                }

                Tap(action: copy) {
                    HStack(spacing: 8) {
                        tt("내 주소 ", .m, 15, C.sub) + addrText(addr, size: 15)
                        Icon("copy-outline", 16, C.sub)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Capsule().fill(C.surface))
                }
                .padding(.top, req > 0 ? 12 : 24)

                TX(Testnet.on ? "\(Testnet.name(network))에서만 보내주세요. 실제 네트워크로 보낸 돈은 이 테스트 통장에 안 보여요."
                              : "\(network.rawValue) 네트워크로만 보내주세요. 다른 네트워크로 보내면 돌려받기 어려워요.",
                   .r, 13, C.amber, lh: 19, align: .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                if let balance = store.st.balance(asset, net: network.rawValue) {
                    TX("지금 잔액 \(qtyText(balance)) · \(asset.uppercased())", .r, 13, C.mute).padding(.top, 10)
                }
                // 비트코인: 아직 블록에 안 들어간 입금은 잔액과 따로 '확인 중'으로 (보낸 쪽이 보냈는데 안 보인다고 걱정하지 않게)
                if network == .bitcoin && store.st.btcIncoming > 0 {
                    TX("확인 중인 입금 \(qtyText(store.st.btcIncoming)) · BTC · 블록에 들어가면 잔액에 더해져요", .r, 13, C.amber, align: .center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                if let url = network.explorer(address: addr) {
                    Tap(action: { openURL(url) }) {
                        HStack(spacing: 4) {
                            TX("블록체인에서 이 주소 잔액 보기", .m, 13, C.sub)
                            Icon("open-outline", 12, C.sub)
                        }
                        .padding(.vertical, 6)
                    }
                    .padding(.top, 4)
                }
                if let error = store.st.networkErrors?[network.rawValue] {
                    TX(error + " · 마지막 확인 잔액이에요", .r, 13, C.red).padding(.top, 6)
                }

                HStack(spacing: 8) {
                    if canRequest {
                        OButton(req > 0 ? "금액 바꾸기" : "금액 정하기", kind: .secondary, icon: "calculator-outline") { draft = 0; open = true }
                    }
                    OButton("공유하기", kind: .secondary, icon: "share-outline", disabled: addr.isEmpty) { sharing = true }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .refreshable { await store.sync() }
    }
}

struct AddressQRView: View {
    let payload: String
    var body: some View {
        if let image = AddressQR.image(payload) {
            Image(uiImage:image).interpolation(.none).resizable().scaledToFit().frame(width:250,height:250).padding(12)
        }
    }
}
enum AddressQR {
    static func image(_ payload: String) -> UIImage? {
        guard let filter = CIFilter(name:"CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8),forKey:"inputMessage")
        filter.setValue("M",forKey:"inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by:CGAffineTransform(scaleX:10,y:10))
        guard let cg = CIContext().createCGImage(scaled,from:scaled.extent) else { return nil }
        return UIImage(cgImage:cg)
    }
    static func shareItems(payload:String,label:String,text:String) -> [Any] {
        guard let qr = image(payload) else { return [text] }
        let image = UIGraphicsImageRenderer(size:CGSize(width:600,height:730)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x:0,y:0,width:600,height:730))
            qr.draw(in:CGRect(x:60,y:50,width:480,height:480))
            (label as NSString).draw(in:CGRect(x:40,y:560,width:520,height:50),withAttributes:[.font:UIFont.boldSystemFont(ofSize:24),.foregroundColor:UIColor.black])
            (payload as NSString).draw(in:CGRect(x:40,y:620,width:520,height:90),withAttributes:[.font:UIFont.systemFont(ofSize:14),.foregroundColor:UIColor.black])
        }
        return [image,text]
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - QR 찍기

/// 스캔 화면 움직임 — 프로토타입의 CSS 곡선을 그대로 옮김
enum ScanMotion {
    /// 링 이동·크기: cubic-bezier(.3,1.25,.5,1) 0.42s (살짝 튕김)
    static let ring = Animation.timingCurve(0.3, 1.25, 0.5, 1, duration: 0.42)
    /// 틈 닫힘: cubic-bezier(.2,.8,.2,1) 0.3s, 0.18s 뒤
    static let close = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3).delay(0.18)
    /// 결과 시트: cubic-bezier(.2,.85,.25,1) 0.38s
    static let sheet = Animation.timingCurve(0.2, 0.85, 0.25, 1, duration: 0.38)
    /// 빛 퍼짐: cubic-bezier(.2,.8,.2,1) 0.45s, 0.48s 뒤
    static let pulse = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45).delay(0.48)
    /// CSS 'ease'
    static func ease(_ d: Double) -> Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: d) }
    static let easeCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.25, y: 0.1),
                                            endControlPoint: UnitPoint(x: 0.25, y: 1))
}

/// Ouryn 로고의 '열린 O' 스캔 링
/// 디자인 기준 280pt(반지름 128, 두께 4, 틈 67°, 점 지름 14) — 크기는 scaleEffect로 바꿔서
/// 프로토타입(SVG)처럼 두께·점도 같이 줄어듦
struct ScanRing: View {
    enum Look: Equatable { case open, closed, amber }

    var look: Look = .open
    var spinning = true
    /// 8초에 한 바퀴 = 45°/초
    var degPerSec: Double = 45
    var sheen = true

    static let size: CGFloat = 280
    private static let openTo: CGFloat = 654.5 / 804.2   // 틈 67° (2πr = 804.2)
    private static let sheenLen: CGFloat = 46 / 804.2
    private static let silver = LinearGradient(stops: [
        .init(color: Color(hex: "#fcfcfc"), location: 0),
        .init(color: .white, location: 0.34),
        .init(color: Color(hex: "#bdbdc2"), location: 0.6),
        .init(color: Color(hex: "#8e8e94"), location: 0.85),
        .init(color: Color(hex: "#e6e6e7"), location: 1),
    ], startPoint: .topLeading, endPoint: .bottomTrailing)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var base: Double = 0          // 멈출 때까지 돈 각도
    @State private var since: Date? = Date()     // 돌기 시작한 시각 (nil = 멈춤)

    private var closed: Bool { look == .closed }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !(spinning || sheen))) { ctx in
            let t = ctx.date
            let spin = reduceMotion ? 0 : base + (since.map { t.timeIntervalSince($0) } ?? 0) * degPerSec
            // 빛: 2.4초마다 한 바퀴, cubic-bezier(.45,.05,.55,.95) ≈ ease-in-out-sine
            let p = (t.timeIntervalSinceReferenceDate / 2.4).truncatingRemainder(dividingBy: 1)
            let sheenDeg = 360 * (1 - cos(.pi * p)) / 2

            ZStack {
                // 링 (은색 ↔ 흰색/노랑은 0.2초 겹쳐 바뀜)
                ring.stroke(Self.silver, style: line(4))
                    .animation(ScanMotion.close, value: closed)
                    .opacity(look == .open ? 1 : 0)
                ring.stroke(look == .amber ? C.amber : C.text, style: line(4))
                    .animation(ScanMotion.close, value: closed)
                    .opacity(look == .open ? 0 : 1)
                // 링 위를 지나가는 빛 (링 모양 안에서만 보임)
                Circle().inset(by: 12)
                    .trim(from: 0, to: Self.sheenLen)
                    .stroke(Color.white.opacity(0.95), style: line(6))
                    .rotationEffect(.degrees(sheenDeg))
                    .mask(Circle().inset(by: 12).trim(from: 0, to: Self.openTo).stroke(style: line(7)))
                    .opacity(sheen && !closed && !reduceMotion ? 1 : 0)
                    .animation(ScanMotion.ease(0.15), value: closed)
                // 틈 가운데 점 — 닫히면 빨려 들어감
                Circle()
                    .fill(look == .amber ? C.amber : Color(hex: "#f4f4f5"))
                    .frame(width: 14, height: 14)
                    .scaleEffect(closed ? 0.2 : 1)
                    .opacity(closed ? 0 : 1)
                    .animation(ScanMotion.ease(0.18).delay(0.2), value: closed)
                    .offset(x: 106.7, y: -70.6)
            }
            .animation(.easeInOut(duration: 0.2), value: look)
            .rotationEffect(.degrees(spin))
            .frame(width: Self.size, height: Self.size)
        }
        .onChange(of: spinning) { _, on in
            rebase(degPerSec)
            since = on ? Date() : nil
        }
        .onChange(of: degPerSec) { old, _ in rebase(old) }
    }

    private var ring: some Shape {
        Circle().inset(by: 12).trim(from: 0, to: closed ? 1 : Self.openTo)
    }

    private func line(_ w: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: w, lineCap: .round) }

    /// 지금까지 돈 각도를 base에 쌓고 기준 시각을 새로 잡음 (멈출 때 그 각도 그대로 멈춤)
    private func rebase(_ speed: Double) {
        guard let s = since else { return }
        base = (base + Date().timeIntervalSince(s) * speed).truncatingRemainder(dividingBy: 360)
        since = Date()
    }
}

/// 링 밖만 어둡게 (가운데 원을 뚫은 사각형) — 위치·크기가 링과 같은 곡선으로 움직임
struct HoleDim: Shape {
    var c: CGPoint
    var d: CGFloat

    var animatableData: AnimatablePair<CGPoint.AnimatableData, CGFloat> {
        get { AnimatablePair(c.animatableData, d) }
        set { c.animatableData = newValue.first; d = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addEllipse(in: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
        return p
    }
}

private struct RingGeo: Equatable {
    var c: CGPoint
    var d: CGFloat
}

private struct Glow {
    var s: CGFloat = 1
    var a: Double = 0
}

private struct ScanResultHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ScanView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let fromSend: Bool
    let onPick: (PayRequest) -> Void
    /// 오른쪽 위 '내 QR' (nil이면 숨김)
    var onMyQR: (() -> Void)? = nil
    /// 탭 바 가운데 O 의 전역 위치 — 주면 링이 거기서 커져 나옴
    var launchFrom: CGRect? = nil
    @State private var introDone = false
    /// O 자리에 있는 동안 (카메라·글자·배경은 아직 투명)
    private var intro: Bool { launchFrom != nil && !introDone && !reduceMotion }

    enum Phase: Equatable { case scan, lock, sheet, err }
    private enum Cam { case checking, live, none, denied }

    @State private var active = false
    @State private var transitionTask: Task<Void, Never>?
    @State private var photoTask: Task<Void, Never>?
    @State private var resultContentHeight: CGFloat = 350
    @State private var readingPhoto = false
    @State private var picking = false
    @State private var cam: Cam = .checking
    @State private var phase: Phase = .scan
    @State private var found: PayRequest? = nil
    @State private var target: CGRect? = nil        // 이 화면 좌표의 QR 위치
    @State private var origin: CGPoint = .zero      // 이 화면의 윈도우 좌표 원점
    @State private var torch = false
    @State private var frozen = false
    @State private var flash = false
    @State private var pulse: CGFloat = 0
    @State private var shake = 0
    @State private var errText = ""
    @State private var hint = false
    @State private var glow = 0
    @State private var lastWarn = Date.distantPast
    @State private var photo: PhotosPickerItem? = nil
    /// 앨범에서 고른 사진 (있으면 카메라 대신 보여줌)
    @State private var still: UIImage? = nil
    @State private var size: CGSize = .zero

    private var title: String {
        if still != nil {
            switch phase {
            case .scan: return "사진에서 QR을 찾고 있어요"
            case .err: return "QR을 찾지 못했어요"
            default: return "QR을 찾았어요"
            }
        }
        switch cam {
        case .none: return "이 기기엔 카메라가 없어요"
        case .denied: return "카메라를 쓸 수 없어요"
        default: return "QR을 동그라미 안에 비춰주세요"
        }
    }
    private var sub: String {
        if still != nil {
            switch phase {
            case .scan: return "조금만 기다려 주세요"
            case .err: return "다른 사진을 골라주세요"
            default: return "주소를 확인하고 있어요"
            }
        }
        switch cam {
        case .none: return "사진 속 QR을 불러오거나 체험용으로 이어가요"
        case .denied: return "설정에서 카메라를 켜거나, 사진 속 QR을 불러와주세요"
        default: return "금액을 요청한 QR이면 금액까지 채워져요"
        }
    }

    private var look: ScanRing.Look {
        switch phase {
        case .scan: return .open
        case .err: return .amber
        case .lock, .sheet: return .closed
        }
    }

    var body: some View {
        GeometryReader { safe in
          GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let scanDiameter = min(ScanRing.size, max(200, h - 440))
            let home = CGPoint(x: w / 2, y: max(safe.safeAreaInsets.top + 150 + scanDiameter / 2, h * 0.43))           // 작은 화면에서도 제목과 겹치지 않게 배치
            let panelHeight = min(h - safe.safeAreaInsets.top - 16, resultContentHeight + 30 + max(16, safe.safeAreaInsets.bottom))
            let avatar = CGPoint(x: w / 2, y: h - panelHeight + 60)      // 결과 시트 아바타 중심
            let geo = ringGeo(home: home, avatar: avatar, scanDiameter: scanDiameter)

            ZStack {
                camera
                    .opacity(intro ? 0 : 1)
                    .animation(ScanMotion.ease(0.3).delay(intro ? 0 : 0.12), value: intro)

                // 결과 시트 뒤 배경 78%
                Color(hex: "#060608").opacity(0.78)
                    .opacity(phase == .sheet ? 1 : 0)
                    .animation(ScanMotion.ease(0.35).delay(0.1), value: phase)
                    .onTapGesture { if phase == .sheet { close() } }
                    .zIndex(1)

                // 인식 순간 번쩍 (흰색 22% → 0)
                Color.white.opacity(flash ? 0.22 : 0)
                    .allowsHitTesting(false)
                    .zIndex(2)

                ringLayer(geo)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(phase == .sheet ? 6 : 3)

                ui(insets: safe.safeAreaInsets)
                    .opacity(intro ? 0 : 1)
                    .animation(ScanMotion.ease(0.3).delay(intro ? 0 : 0.12), value: intro)
                    .opacity(phase == .sheet ? 0 : 1)
                    .animation(ScanMotion.ease(0.2), value: phase)
                    .allowsHitTesting(phase == .scan || phase == .err)
                    .accessibilityHidden(phase == .sheet)
                    .zIndex(4)

                // 링 바로 아래: 오류 안내 · 도움말
                VStack(spacing: 0) {
                    Spacer().frame(height: home.y + scanDiameter / 2 + 20)
                    if phase == .err { errPill.padding(.horizontal, 24) }
                    if hint && phase == .scan { hintCard.padding(.horizontal, 24) }
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)
                .zIndex(4)

                resultSheet(height: panelHeight, bottom: safe.safeAreaInsets.bottom)
                    .zIndex(5)
            }
            .frame(width: w, height: h)
            .onAppear { origin = g.frame(in: .global).origin; size = g.size }
            .onChange(of: g.size) { _, v in origin = g.frame(in: .global).origin; size = v }
        }
          .ignoresSafeArea()
        }
        .background(Color(hex: "#0E0E10").opacity(intro ? 0 : 1).animation(ScanMotion.ease(0.3).delay(intro ? 0 : 0.12), value: intro))
        .onAppear { active = true; checkCamera(); startIntro() }
        .onDisappear { invalidate(); active = false }
        .onChange(of: scenePhase) { _, next in
            if next == .active { active = true; checkCamera() }
            else { invalidate(); active = false; close() }
        }
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        // 8초 동안 못 찾으면 도움말 + 손전등 반짝
        .task(id: "\(phase)-\(cam)-\(active)") {
            if phase != .scan { if hint { hint = false }; return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, phase == .scan, cam == .live, active else { return }
            hint = true
            glow += 1
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photoTask?.cancel()
            readingPhoto = true
            photoTask = Task { @MainActor in
                let data = try? await item.loadTransferable(type: Data.self)
                guard !Task.isCancelled, active else { return }
                photo = nil
                guard let data, let img = UIImage(data: data) else {
                    readingPhoto = false
                    lastWarn = .distantPast
                    fail("사진을 열지 못했어요")
                    return
                }
                // 1) 고른 사진을 보여주고 링은 찾는 중
                withAnimation(ScanMotion.ease(0.25)) { still = img }
                let found = await Task.detached(priority: .userInitiated) { readQRStill(fromImageData: data) }.value
                // 사진을 본 다음에 링이 움직이도록 잠깐
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(650)) }
                guard !Task.isCancelled, active else { return }
                readingPhoto = false
                // 2) 사진 속 QR 위치로 링이 붙음
                if let found { handle(found.text, nil, stillRect: found.rect) }
                else { lastWarn = .distantPast; fail("사진에서 QR을 찾지 못했어요") }
            }
        }
    }

    // MARK: 층

    @ViewBuilder private var camera: some View {
        ZStack {
            Color(hex: torch ? "#26262A" : "#0E0E10")
            if cam == .live && active {
                QRCamera(torch: torch, paused: phase != .scan || readingPhoto || still != nil, frozen: frozen) { text, rect in
                    handle(text, rect)
                }
            }
            if let still {
                Color.black
                Image(uiImage: still)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("고른 사진")
            }
        }
    }

    private func ringLayer(_ geo: RingGeo) -> some View {
        ZStack {
            // 링 밖 어둡게 62% (결과 시트에선 0.35초에 걸쳐 사라짐)
            HoleDim(c: geo.c, d: geo.d)
                .fill(Color(hex: "#060608"), style: FillStyle(eoFill: true))
                .animation(ScanMotion.ring, value: geo)
                .opacity(phase == .sheet ? 0 : 0.62)
                .animation(ScanMotion.ease(0.35), value: phase)
                .allowsHitTesting(false)

            ZStack {
                // 아바타 바탕 (결과 시트에서만)
                Circle().fill(C.surface2)
                    .frame(width: geo.d, height: geo.d)
                    .opacity(phase == .sheet ? 1 : 0)
                    .animation(ScanMotion.ease(0.25).delay(0.25), value: phase)

                ScanRing(look: look,
                         spinning: active && (phase == .scan || phase == .err),
                         degPerSec: hint ? 360.0 / 14 : 45,
                         sheen: active && (phase == .scan || phase == .err))
                    .scaleEffect(geo.d / ScanRing.size)
                    .frame(width: geo.d, height: geo.d)
                    .opacity(hint ? 0.6 : 1)
                    .animation(ScanMotion.ease(0.3), value: hint)

                // 빛 퍼짐: 틈이 닫히는 0.48초에 1 → 1.45배로 커지며 사라짐
                Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                    .frame(width: geo.d, height: geo.d)
                    .scaleEffect(1 + 0.45 * pulse)
                    .opacity(phase == .lock ? 0.75 * (1 - pulse) : 0)
                    .animation(nil, value: phase)

                Group {
                    if let f = found, CoinArt.asset(f.asset) != nil || CoinArt.network(f.network) != nil {
                        // 받는 코인 로고 + 네트워크 로고
                        CoinLogo(asset: f.asset, network: f.network, size: 46, ring: C.surface2)
                    } else {
                        Icon("wallet-outline", 26, C.text)
                    }
                }
                    .opacity(phase == .sheet ? 1 : 0)
                    .animation(ScanMotion.ease(0.2).delay(0.3), value: phase)
            }
            .frame(width: geo.d, height: geo.d)
            // 오류: 좌우 -6 · 6 · -5 · 3 · 0 (0.32초, 구간마다 ease)
            .keyframeAnimator(initialValue: CGFloat(0), trigger: shake) { v, x in
                v.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-6, duration: 0.064, timingCurve: ScanMotion.easeCurve)
                    LinearKeyframe(6, duration: 0.064, timingCurve: ScanMotion.easeCurve)
                    LinearKeyframe(-5, duration: 0.064, timingCurve: ScanMotion.easeCurve)
                    LinearKeyframe(3, duration: 0.064, timingCurve: ScanMotion.easeCurve)
                    LinearKeyframe(0, duration: 0.064, timingCurve: ScanMotion.easeCurve)
                }
            }
            .position(geo.c)
            .animation(ScanMotion.ring, value: geo)
        }
    }

    private func ui(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack {
                Tap(action: closeScan) {
                    Icon("close", 26, .white).frame(width: 44, height: 44)
                }
                .accessibilityLabel("닫기")
                Spacer()
                if let my = onMyQR {
                    Tap(action: { invalidate(); my() }) {
                        TX("내 QR", .sb, 14, .white)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 12)
            .padding(.top, insets.top)

            VStack(spacing: 8) {
                TX(title, .b, 22, .white, align: .center)
                TX(sub, .r, 15, Color.white.opacity(0.72), align: .center)
            }
            .padding(.top, 28)
            .padding(.horizontal, 24)

            Spacer()
            controls
                .disabled(readingPhoto || phase == .lock)
                .overlay(alignment: .top) { if readingPhoto && still == nil { ProgressView("사진을 읽고 있어요").tint(.white).offset(y: -36) } }
                .padding(.bottom, insets.bottom + 33)
        }
    }

    @ViewBuilder private var controls: some View {
        if cam == .live {
            HStack(spacing: 72) {
                PhotosPicker(selection: $photo, matching: .images) {
                    roundButton("images-outline", "사진", on: false)
                }
                .buttonStyle(TapStyle())
                .accessibilityLabel("사진에서 불러오기")

                Tap(action: { haptic(.select); torch.toggle() }) {
                    roundButton(torch ? "flashlight" : "flashlight-outline", "손전등", on: torch, glowing: true)
                }
                .accessibilityLabel(torch ? "손전등 끄기" : "손전등 켜기")
            }
        } else if cam != .checking {
            VStack(spacing: 10) {
                // 체험용 QR 은 카메라가 아예 없는 기기(시뮬레이터 등)에서만. 실제 폰에서 권한을 끈 경우엔 보여주지 않음
                if cam == .none {
                    Tap(action: { handle(nil, nil, demo: SCAN_DEMO) }) {
                        pill("sparkles-outline", "체험용 QR 인식하기", strong: true)
                    }
                }
                if cam == .denied {
                    Tap(action: {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }) { pill("settings-outline", "설정 열기") }
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    pill("images-outline", "사진에서 불러오기")
                }
                .buttonStyle(TapStyle())
            }
        }
    }

    private func roundButton(_ icon: String, _ label: String, on: Bool, glowing: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(on ? C.text : Color.white.opacity(0.14))
                Icon(icon, 22, on ? C.ink : .white)
            }
            .frame(width: 56, height: 56)
            .background {
                if glowing && !reduceMotion {
                    // box-shadow 0 → 10pt 퍼짐, 1.6초 ease-out × 2번
                    Circle().fill(Color.white)
                        .keyframeAnimator(initialValue: Glow(), trigger: glow) { v, gl in
                            v.scaleEffect(gl.s).opacity(gl.a)
                        } keyframes: { _ in
                            KeyframeTrack(\.s) {
                                LinearKeyframe(CGFloat(76) / 56, duration: 0.8, timingCurve: .easeOut)
                                LinearKeyframe(1, duration: 0.8, timingCurve: .easeOut)
                                LinearKeyframe(CGFloat(76) / 56, duration: 0.8, timingCurve: .easeOut)
                                LinearKeyframe(1, duration: 0.8, timingCurve: .easeOut)
                            }
                            KeyframeTrack(\.a) {
                                LinearKeyframe(0.45, duration: 0)
                                LinearKeyframe(0, duration: 0.8, timingCurve: .easeOut)
                                LinearKeyframe(0.45, duration: 0.8, timingCurve: .easeOut)
                                LinearKeyframe(0, duration: 0.8, timingCurve: .easeOut)
                                LinearKeyframe(0.45, duration: 0.8, timingCurve: .easeOut)
                                LinearKeyframe(0, duration: 0)
                            }
                        }
                }
            }
            TX(label, .m, 12, on ? .white : Color.white.opacity(0.8))
        }
    }

    private var errPill: some View {
        VStack(spacing: 6) {
            TX(errText, .sb, 14, C.amber, align: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(C.amber.opacity(0.16)))
            TX("결제 요청 QR이나 지갑 주소 QR을 비춰주세요", .r, 13, Color.white.opacity(0.75), align: .center)
        }
        .opacity(phase == .err ? 1 : 0)
        .offset(y: phase == .err ? 0 : 6)
        .animation(ScanMotion.ease(0.15), value: phase)
    }

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            TX("잘 안 읽히나요?", .b, 14, .white)
            TX("한 뼘쯤 떨어져서 QR 전체가 동그라미 안에 들어오게 해보세요. 어두우면 손전등을 켜보세요.",
               .r, 14, Color.white.opacity(0.75), lh: 21)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "rgba(26,26,30,0.92)")))
        .opacity(hint && phase == .scan ? 1 : 0)
        .animation(ScanMotion.ease(0.3), value: hint)
    }

    private func resultSheet(height: CGFloat, bottom: CGFloat) -> some View {
        let on = phase == .sheet
        return VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                Capsule().fill(C.faint).frame(width: 36, height: 5).padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onEnded { if $0.translation.height > 60 { close() } })
                ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 76)   // 링이 아바타가 되어 들어오는 자리
                    if let r = found {
                        let name = store.st.nameOf(r.to)
                        TX(name != nil ? "\(name ?? "")님의 지갑이에요" : "지갑을 찾았어요", .b, 22)
                        AddrText(addr: r.to, size: 14, base: C.mute).padding(.top, 6)
                        if r.test { TestnetChip(text: "테스트넷 주소").padding(.top, 12) }
                        if let n = r.network {
                            let netLabel: String = r.test ? (WalletNetwork(rawValue: n).map { Testnet.name($0) } ?? n) : n + " 네트워크"
                            let chipLabel: String = r.asset.map { $0.uppercased() + " · " + netLabel } ?? netLabel
                            HStack(spacing: 6) {
                                CoinLogo(network: n, size: 16, ring: C.surface2)
                                TX(chipLabel, .sb, 13, C.sub)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Capsule().fill(C.surface2))
                            .padding(.top, 12)
                        }
                        if let q = r.qty, let a = r.asset {
                            // 정확한 수량 요청 (ERC-681): 받는 사람·코인·네트워크·수량을 그대로 보여줌
                            VStack(spacing: 4) {
                                TX("\(q) \(a.uppercased()) 요청", .b, 20)
                                TX("\(assetFullName(a)) · \(r.network ?? "") 네트워크", .r, 13, C.sub)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(C.surface2))
                            .padding(.top, 16)
                        } else if let u = r.usd {
                            VStack(spacing: 4) {
                                TX("\(wonOf(u)) 요청", .b, 20)
                                TX("\(assetFullName(r.asset ?? "usdc")) \(dollar(u)) · \(DOLLAR_NET) 네트워크", .r, 13, C.sub)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(C.surface2))
                            .padding(.top, 16)
                        }
                        // 테스트넷 주소는 테스트 통장에서만, 실제 네트워크라고 밝힌 주소는 진짜 통장에서만
                        let needTest = r.test && !store.st.inTest
                        let needReal = r.mainnet && store.st.inTest
                        if needTest || needReal {
                            TX(needTest ? "테스트넷 주소라 테스트 통장에서만 보낼 수 있어요" : "실제 네트워크 주소라 테스트 통장에서는 보낼 수 없어요",
                               .r, 13, needTest ? C.down : C.amber, align: .center)
                                .padding(.top, 14)
                        }
                        OButton(needTest ? "테스트 통장으로 바꾸고 보내기" : needReal ? "진짜 통장으로 바꾸고 보내기"
                                : (r.usd != nil || r.qty != nil ? "금액 확인하고 보내기" : "보내기"), disabled: picking) {
                            guard !picking else { return }; picking = true
                            if needTest { store.openTestAccount() } else if needReal { store.leaveTestAccount() }
                            invalidate(); onPick(r)
                        }
                            .padding(.top, 16)
                        Button("다시 스캔하기", action: close)
                            .font(.custom("Pretendard-Medium", size: 15))
                            .foregroundStyle(C.sub).frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 22)
                .background(GeometryReader { content in
                    Color.clear.preference(key: ScanResultHeightKey.self, value: content.size.height)
                })
                // 결과는 링이 도착한 뒤 나타남
                .opacity(on ? 1 : 0)
                .offset(y: on ? 0 : 8)
                .animation(ScanMotion.ease(0.25).delay(0.3), value: on)
                }
                .onPreferenceChange(ScanResultHeightKey.self) { resultContentHeight = $0 }
                .padding(.bottom, max(16, bottom))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).fill(C.sheet))
            .offset(y: on ? 0 : height * 1.05)
            .animation(on ? ScanMotion.sheet.delay(0.05) : ScanMotion.sheet, value: on)
            .allowsHitTesting(on)
            .accessibilityHidden(!on)
            .accessibilityAction(.escape) { close() }
        }
    }

    // MARK: 동작

    private func ringGeo(home: CGPoint, avatar: CGPoint, scanDiameter: CGFloat) -> RingGeo {
        // 탭 바 O 자리 (로고 크기) → 0.42초 동안 home 으로
        if intro, phase == .scan, let f = launchFrom {
            return RingGeo(c: CGPoint(x: f.midX - origin.x, y: f.midY - origin.y), d: 40)
        }
        switch phase {
        case .scan, .err:
            return RingGeo(c: home, d: scanDiameter)
        case .lock:
            // 실제 QR에 맞게: target = QR 모서리까지 감싸는 원. 링 선 안쪽(280 틀에서 반지름 126)이 그 원보다 8pt 바깥
            if let t = target {
                let r: CGFloat = max(t.width, t.height) / 2
                let need: CGFloat = (r + 8) * ScanRing.size / 126
                let d: CGFloat = min(ScanRing.size * 2.4, max(110, need))
                return RingGeo(c: CGPoint(x: t.midX, y: t.midY), d: d)
            }
            return RingGeo(c: home, d: 196)   // 사진·체험용처럼 위치를 모를 때
        case .sheet:
            return RingGeo(c: avatar, d: 64)
        }
    }

    private func go(_ p: Phase) {
        phase = p
    }

    private func handle(_ text: String?, _ rect: CGRect?, demo: PayRequest? = nil, stillRect: CGRect? = nil) {
        guard active, phase == .scan, !picking else { return }
        if let d = demo { lock(d, at: nil); return }
        guard let text, let r = parsePay(text) else {
            fail("Ouryn에서 읽을 수 없는 QR이에요")
            return
        }
        if r.to == store.st.myAddr {
            fail("내 지갑 QR이에요")
            return
        }
        lock(r, at: rect, local: stillRect.flatMap { viewRect($0) })
    }

    /// 사진 기준 0~1 위치 → 화면 위치 (scaledToFit 으로 가운데 놓인 사진)
    private func viewRect(_ n: CGRect) -> CGRect? {
        guard let img = still, img.size.width > 0, img.size.height > 0, size.width > 0 else { return nil }
        let k = min(size.width / img.size.width, size.height / img.size.height)
        let w = img.size.width * k, h = img.size.height * k
        let x = (size.width - w) / 2, y = (size.height - h) / 2
        return CGRect(x: x + n.minX * w, y: y + n.minY * h, width: n.width * w, height: n.height * h)
    }

    /// 0ms 화면 멈춤 · 번쩍 → 0–420ms 링 이동 → 180–480ms 틈 닫힘 → 480ms 햅틱 + 빛 퍼짐 → 650ms 결과 시트
    private func lock(_ r: PayRequest, at rect: CGRect?, local: CGRect? = nil) {
        found = r
        target = local ?? rect.flatMap { $0.isEmpty ? nil : $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        frozen = true
        go(.lock)
        transitionTask?.cancel()
        if reduceMotion {
            haptic(.success)
            go(.sheet)
            return
        }
        noAnim { flash = true; pulse = 0 }
        transitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, active else { return }
            withAnimation(.easeOut(duration: 0.22)) { flash = false }
            withAnimation(ScanMotion.pulse) { pulse = 1 }
            do {
                try await Task.sleep(for: .milliseconds(480))
                guard active, phase == .lock else { return }
                haptic(.success)
                try await Task.sleep(for: .milliseconds(170))
                guard active, phase == .lock else { return }
                go(.sheet)
            } catch { return }
        }
    }

    private func fail(_ t: String) {
        guard active, Date().timeIntervalSince(lastWarn) >= 2.5 else { return }
        lastWarn = Date()
        haptic(.error)
        errText = t
        go(.err)
        if !reduceMotion { shake += 1 }
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(1700)) } catch { return }
            guard active, phase == .err else { return }
            go(.scan)
            if still != nil { withAnimation(ScanMotion.ease(0.25)) { still = nil } }
        }
    }

    /// O 에서 열렸으면: 다음 프레임에 링이 화면 가운데로 (ScanMotion.ring)
    private func startIntro() {
        guard launchFrom != nil, !introDone else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            introDone = true
        }
    }

    /// 닫기 — O 에서 열렸으면 링이 다시 O 자리로 작아진 뒤 닫힘
    private func closeScan() {
        invalidate()
        guard launchFrom != nil, !reduceMotion, phase == .scan || phase == .err, still == nil else {
            dismiss()
            return
        }
        transitionTask?.cancel()
        go(.scan)
        introDone = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { dismiss() }
        }
    }

    private func invalidate() {
        transitionTask?.cancel()
        photoTask?.cancel()
        readingPhoto = false
        torch = false
    }

    private func close() {
        transitionTask?.cancel()
        frozen = false
        flash = false
        pulse = 0
        picking = false
        found = nil
        target = nil
        still = nil
        go(.scan)
    }

    private func checkCamera() {
        guard QRScannerView.available else { cam = .none; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cam = .live
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { cam = granted ? .live : .denied }
            }
        default: cam = .denied
        }
    }

    private func pill(_ icon: String, _ label: String, strong: Bool = false) -> some View {
        HStack(spacing: 8) {
            Icon(icon, 18, strong ? C.ink : .white)
            TX(label, .m, 15, strong ? C.ink : .white)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Capsule().fill(strong ? AnyShapeStyle(metalGradient(vertical: true)) : AnyShapeStyle(Color.white.opacity(0.12))))
    }
}

// MARK: - 가까이 있는 사람에게

private let R: CGFloat = 150
private let POS: [(CGFloat, CGFloat)] = [(-0.62, -0.55), (0.66, -0.2), (-0.18, 0.72)]

struct NearbyView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let fromSend: Bool
    let onPick: (String) -> Void

    @State private var shown = 0
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Tap(action: { dismiss() }) { Icon("close", 26, C.text).padding(16) }.padding(-12)
                    .accessibilityLabel("뒤로")
                Spacer()
            }
            .frame(height: 52)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 0) {
                TX("가까이 있는 사람에게", .b, 26)
                TX("상대방도 이 화면을 열면 서로 보여요.\n주소를 몰라도 바로 보낼 수 있어요.", .r, 15, C.sub, lh: 22).padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            ZStack {
                ForEach([CGFloat(1), 0.66, 0.33], id: \.self) { k in
                    Circle().strokeBorder(C.line, lineWidth: 1).frame(width: R * 2 * k, height: R * 2 * k)
                }
                // 퍼지는 물결 3개 (0.8초 간격)
                TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { tl in
                    let t = tl.date.timeIntervalSince(start)
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            let local = t - Double(i) * 0.8
                            let p = reduceMotion ? 0.35 * Double(i + 1) : (local < 0 ? 0 : Curve.outQuad(local.truncatingRemainder(dividingBy: 2.4) / 2.4))
                            Circle().fill(C.blue)
                                .frame(width: R * 2, height: R * 2)
                                .scaleEffect(0.2 + 0.8 * p)
                                .opacity(reduceMotion ? 0.08 : (local < 0 ? 0 : 0.22 * (1 - p)))
                        }
                    }
                }
                ZStack { Circle().fill(C.surface); Logo(size: 72 * LOGO_IN_CIRCLE) }.frame(width: 72, height: 72)

                ForEach(0..<shown, id: \.self) { i in
                    let p = NEARBY[i]
                    Person(name: store.st.nameOf(p.addr), device: p.device) { pick(p.addr) }
                        .offset(x: POS[i].0 * R, y: POS[i].1 * R)
                }
            }
            .frame(width: R * 2, height: R * 2)
            .frame(maxHeight: .infinity)

            TX(shown > 0 ? "\(shown)명을 찾았어요 · 눌러서 보내기" : "주변을 찾고 있어요…", .r, 14, C.mute)
                .padding(.bottom, 28)
        }
        .background(C.bg.ignoresSafeArea())
        .onAppear {
            start = Date()
            for (i, ms) in [1.2, 2.3, 3.6].enumerated() {
                after(ms) { haptic(.light); shown = i + 1 }
            }
        }
    }

    private func pick(_ addr: String) {
        haptic(.medium)
        onPick(addr)
    }
}

private struct Person: View {
    let name: String?
    let device: String
    let onPress: () -> Void
    @State private var a: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Tap(action: onPress) {
            VStack(spacing: 0) {
                if let n = name {
                    Avatar(name: n, size: 54, ring: true)
                } else {
                    Avatar(icon: "phone-portrait", color: C.surface3, size: 54, ring: true)
                }
                TX(name ?? device, .sb, 13, lines: 1).padding(.top, 6)
            }
            .frame(width: 80)
        }
        .opacity(Double(a))
        .scaleEffect(a)
        .onAppear { if reduceMotion { a = 1 } else { withAnimation(Ease.rnSpring(friction: 5, tension: 120)) { a = 1 } } }
    }
}
