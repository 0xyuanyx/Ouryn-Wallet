import SwiftUI
import WalletCore

struct SavedRecipient: Codable, Identifiable, Equatable {
 var network: String
 var address: String
 var name: String
 var id: String { network + "|" + (["이더리움","맨틀","Avalanche C-Chain"].contains(network) ? address.lowercased() : address) }
}

/// 보낸 적 있는 주소 (네트워크+주소 기준 중복 제거, 최신순)
func recentSends(_ st: AppState, limit: Int) -> [Tx] {
 var seen = Set<String>()
 return st.tx.filter { t in
  guard t.type == .send, !t.hash.isEmpty, (t.status == .done || t.via == "전파 완료"), let a = t.addr else { return false }
  return seen.insert(t.network + "|" + (["이더리움","Avalanche C-Chain","맨틀"].contains(t.network) ? a.lowercased() : a)).inserted
 }.prefix(limit).map { $0 }
}

struct TransferFlow: View {
 @EnvironmentObject var store: Store
 @EnvironmentObject var router: Router
 @Environment(\.dismiss) private var dismiss
 @Environment(\.scenePhase) private var scenePhase
 let initial: PayRequest?
 @State private var network = WalletNetwork.tron
 @State private var asset = "usdt"
 @State private var to = ""
 @State private var amount = ""
 @State private var quote: TransferQuote?
 @State private var busy = false
 @State private var error = ""
 @State private var hash: String?
 @State private var scan = false
 @State private var name = ""
 @State private var generation = 0
 @State private var active = true
 @State private var showSent = false
 @State private var hasClip = false
 @State private var picking = false
 @State private var pickToken: String? = nil
 @State private var testReq = false   // QR 이 테스트넷이라고 밝힘
 @State private var mainReq = false   // QR 이 실제 네트워크라고 밝힘
 @State private var reqTo = ""
 @State private var askPin = false     // Face ID 등록이 바뀌었거나 생체인증 없는 지갑 → 앱 비밀번호 먼저
 @State private var pinSub = ""
 @State private var askWords = false   // 12단어로 보내기
 @State private var offerWords = false // Face ID 로 못 열었을 때 '12단어로 보내기' 버튼
 @State private var netKey = ""        // 0x 주소에서 사용자가 확인한 네트워크 ("주소|네트워크")

 private var recent: [Tx] { recentSends(store.st, limit: 8) }
 private var detected: [WalletNetwork] { WalletNetwork.detect(to) }
 /// 0x 주소인데 0x 네트워크가 아닌 걸 골랐을 때
 private var mismatch: Bool { !detected.isEmpty && !detected.contains(network) }
 private var cleanTo: String { to.trimmingCharacters(in: .whitespacesAndNewlines) }
 /// 0x 주소처럼 여러 네트워크에 맞는 주소 → 칩에서 직접 확인해야 진행
 private var ambiguous: Bool { detected.count > 1 }
 private var netConfirmed: Bool { !ambiguous || netKey == cleanTo.lowercased() + "|" + network.rawValue }
 /// 그 네트워크에서 지금 고른 코인과 같은 종류의 id (맨틀 USDT = usdt0). 없으면 nil
 private func assetOn(_ n: WalletNetwork) -> String? {
  let t = TokenCatalog.token(of: asset)
  return n.assets.first { TokenCatalog.token(of: $0) == t }
 }
 private func balanceOn(_ n: WalletNetwork, _ a: String) -> Decimal {
  guard let raw = store.st.networkBalances?[n.rawValue]?[a] else { return 0 }
  return ExactAmount.display(raw: raw, decimals: n.decimals(a))
 }
 /// 이 주소로 보내서 완료된 마지막 네트워크 (후보 안에서만)
 private func lastSentNet(_ addr: String, among: [WalletNetwork]) -> WalletNetwork? {
  let a = addr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  guard !a.isEmpty else { return nil }
  return store.st.tx
   .filter { $0.type == .send && $0.status == .done && ($0.addr ?? "").lowercased() == a }
   .sorted { $0.ts > $1.ts }
   .compactMap { WalletNetwork(rawValue: $0.network) }
   .first { among.contains($0) }
 }
 private var invalid: Bool { to.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 && detected.isEmpty && !needTest && !needReal }
 /// 받는 주소가 지금 통장의 같은 네트워크 주소인지 (EVM·bech32 주소는 대소문자 무시)
 /// 내 주소로 보내면 수수료만 나가서 막음 — 서버 견적 단계와 같은 정책을 입력 단계에서 먼저 알려줌
 private var isSelf: Bool {
  guard let mine = store.st.address(net: network.rawValue), !cleanTo.isEmpty else { return false }
  let caseless = network.isEVM || network == .bitcoin || network == .cardano
  return caseless ? mine.lowercased() == cleanTo.lowercased() : mine == cleanTo
 }
 /// 테스트넷 주소는 테스트 통장에서만, 실제 네트워크 주소는 진짜 통장에서만
 private var needTest: Bool { !store.st.inTest && (testReq || Testnet.looksTest(to)) }
 private var needReal: Bool { store.st.inTest && (mainReq || Testnet.looksMain(to)) }
 private var balance: Decimal? {
  guard let raw = store.st.networkBalances?[network.rawValue]?[asset] else { return nil }
  return ExactAmount.display(raw: raw, decimals: network.decimals(asset))
 }
 /// 수수료를 따로 내는 토큰만 '최대' (코인 자체는 수수료만큼 남겨야 해서 제외)
 private var maxable: Bool { ["usdt", "usdc", "usdt0"].contains(asset) }

 var body: some View {
  NavigationStack {
   ScrollView(showsIndicators: false) {
    VStack(alignment: .leading, spacing: 0) {
     if let hash { doneView(hash) }
     else if let quote { quoteView(quote) }
     else { form }
     if !error.isEmpty { TX(error, .r, 14, C.red, lh: 20).padding(.top, 12) }
    }
    .padding(.horizontal, 24)
    .padding(.top, 8)
    .padding(.bottom, 40)
    .frame(maxWidth: .infinity, alignment: .leading)
    .disabled(busy)
   }
   .scrollDismissesKeyboard(.interactively)
   .background(C.bg.ignoresSafeArea())
   .toolbar {
    ToolbarItem(placement: .topBarLeading) {
     Button { dismiss() } label: { Icon("close", 24, C.text) }
      .disabled(busy)
      .accessibilityLabel("닫기")
    }
   }
   .navigationDestination(isPresented: $showSent) {
    SentAddressesView(recent: recentSends(store.st, limit: 30)) { req in apply(req) }
     .environmentObject(store).environmentObject(router)
   }
   .onAppear { active = true; refreshClip(); if let initial { apply(initial) } }
   .onDisappear { active = false; generation += 1 }
   .onChange(of: scenePhase) { _, p in if p == .active { refreshClip() } }
   .onChange(of: network) { _, n in if !n.assets.contains(asset) { asset = n.assets[0] }; quote = nil; error = "" }
   .onChange(of: to) { _, v in
    // 주소 모양으로 네트워크 자동 선택 (0x 주소는 셋 중 하나라 직접 고름)
    if v != reqTo { testReq = false; mainReq = false }
    let d = WalletNetwork.detect(v)
    if d.count == 1, d[0] != network { network = d[0] }
    if d.count > 1, netKey != v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "|" + network.rawValue,
       let last = lastSentNet(v, among: d) { pickNet(last) }
   }
   .sheet(isPresented: $picking) { pickerSheet }
   .fullScreenCover(isPresented: $scan) {
    ScanView(fromSend: true) { req in scan = false; apply(req) }
     .environmentObject(store).environmentObject(router)
   }
   .fullScreenCover(isPresented: $askPin) {
    PinGate(title: "간편 비밀번호", sub: pinSub) { ok in
     askPin = false
     guard ok, let q = quote else { return }
     if PinVault.hardLocked {
      // 10번 넘게 틀린 뒤에 맞힌 비밀번호는 믿지 않음 → 12단어로
      offerWords = true
      error = "비밀번호를 여러 번 틀려서 지금은 12단어로만 보낼 수 있어요"
      after(0.4) { askWords = true }
     } else {
      unlockAndSend(q)
     }
    }
    .environmentObject(store)
   }
   .fullScreenCover(isPresented: $askWords) {
    WordsEntry(title: "12단어로 보내기",
               sub: "Face ID를 쓸 수 없을 때는 지금 통장의 12단어로 확인하고 보내요. 입력한 단어는 저장하지 않아요.",
               button: "확인하고 보내기",
               onCancel: { askWords = false }) { w in
     guard let q = quote else { return "보낼 내용을 다시 확인해주세요" }
     guard store.wordsMatchCurrent(w) else { return "지금 통장의 12단어가 아니에요. 적어둔 종이를 다시 확인해주세요." }
     askWords = false
     // 12단어 = 가장 확실한 본인 확인 → 잠금 풀고 지금 Face ID 등록을 기준으로, 없어진 항목은 다시 저장
     PinVault.clearHardLock()
     Biometry.accept()
     WalletKeys.repair(words: w, wallet: WalletKeys.active.wallet)
     busy = true
     Task { @MainActor in await send(q, mnemonic: w) }
     return nil
    }
   }
  }
 }

 // MARK: 입력

 @ViewBuilder private var form: some View {
  HStack(spacing: 8) {
   TX("보내기", .b, 26)
   if store.st.inTest { TestnetChip(text: "테스트 통장에서") }
  }
  assetMenu.padding(.top, 20)

  TX("받는 주소", .sb, 13, C.sub).padding(.top, 22)
  AddressField(text: $to, onScan: { scan = true }).padding(.top, 6)
  if mismatch && !ambiguous {
   TX("\(detected.map(\.rawValue).joined(separator: "·")) 주소예요. 위에서 네트워크를 골라주세요", .r, 13, C.amber, lh: 19).padding(.top, 8)
  } else if invalid {
   TX("지갑 주소 형식이 아니에요", .r, 13, C.red).padding(.top, 8)
  } else if isSelf {
   TX("지금 통장의 내 주소예요. 내 주소로는 보낼 수 없어요", .r, 13, C.red).padding(.top, 8)
  }
  if needTest || needReal { accountGate }
  if ambiguous && !needTest && !needReal { networkChips }
  if to.isEmpty && hasClip {
   Tap(action: { applyText(UIPasteboard.general.string ?? "") }) {
    HStack(spacing: 8) {
     Icon("clipboard-outline", 16, C.blueText)
     TX("복사한 주소 붙여넣기", .r, 13, C.blue)
     Spacer(minLength: 0)
     TX("붙여넣기", .b, 13, C.text)
    }
    .padding(.horizontal, 12)
    .frame(height: 44)
    .background(RoundedRectangle(cornerRadius: 12).fill(C.blueSoft))
   }
   .padding(.top, 8)
  }

  if !recent.isEmpty {
   header("최근 보낸 주소", more: "전체 보기").padding(.top, 26)
   ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 8) {
     ForEach(recent) { t in
      Tap(action: { apply(PayRequest(to: t.addr ?? "", network: t.network, asset: t.assetId)) }) {
       HStack(spacing: 10) {
        CoinLogo(network: t.network, size: 28, ring: C.surface)
        VStack(alignment: .leading, spacing: 2) {
         TX("\(t.network) · \(t.assetId.uppercased())", .b, 12, lines: 1)
         AddrText(addr: t.addr ?? "", size: 12)
        }
       }
       .padding(.horizontal, 12)
       .frame(height: 60)
       .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
      }
     }
    }
    .padding(.horizontal, 24)
   }
   .padding(.horizontal, -24)
   .padding(.top, 10)
  }

  HStack(alignment: .firstTextBaseline) {
   TX("보낼 수량", .b, 15)
   Spacer()
   if let b = balance {
    TX("잔액 \(NSDecimalNumber(decimal: b).stringValue) \(asset.uppercased())", .r, 13, C.sub, lines: 1)
    if maxable && b > 0 {
     Tap(action: { amount = NSDecimalNumber(decimal: b).stringValue }) {
      TX("최대", .sb, 13, C.text).padding(.leading, 6).frame(minHeight: 32)
     }
    }
   }
  }
  .padding(.top, 26)
  HStack(spacing: 8) {
   TextField("", text: $amount, prompt: Text("0").foregroundColor(C.faint))
    .keyboardType(.decimalPad)
    .font(pfont(.b, 22))
    .foregroundColor(C.text)
    .tint(C.text)
   if !amount.isEmpty {
    Button { amount = "" } label: { Icon("close-circle", 20, C.mute).frame(width: 32, height: 44) }
     .buttonStyle(.plain)
     .accessibilityLabel("수량 지우기")
   }
   TX(asset.uppercased(), .b, 13)
    .padding(.horizontal, 9).padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 8).fill(C.surface3))
  }
  .padding(.horizontal, 16)
  .frame(height: 60)
  .background(RoundedRectangle(cornerRadius: 14).fill(C.surface))
  .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.line, lineWidth: 1))
  .padding(.top, 8)

  OButton(busy ? "수수료 확인 중" : "수수료 확인",
          disabled: busy || to.isEmpty || amount.isEmpty || (mismatch && !ambiguous) || !netConfirmed || invalid || isSelf || needTest || needReal) { prepare() }
   .padding(.top, 18)

  let saved = Array((store.st.savedRecipients ?? []).suffix(2).reversed())
  if !saved.isEmpty {
   header("주소록", more: "모두 보기", size: 18).padding(.top, 28)
   ForEach(saved) { r in
    Tap(action: { apply(PayRequest(to: r.address, network: r.network)) }) {
     RecipientRow(r: r)
    }
    .padding(.top, 8)
   }
  }
 }

 private var assetMenu: some View {
  Tap(action: { pickToken = nil; picking = true }) {
   HStack(spacing: 12) {
    CoinLogo(asset: asset, network: netConfirmed ? network.rawValue : nil, size: 40, ring: C.surface)
    VStack(alignment: .leading, spacing: 2) {
     TX(asset.uppercased(), .b, 17)
     TX(netConfirmed ? "\(network.rawValue) 네트워크" : "네트워크는 아래에서 골라요", .r, 13, C.sub)
    }
    Spacer(minLength: 0)
    TX("바꾸기", .m, 13, C.sub)
    Icon("chevron-forward", 16, C.mute)
   }
   .padding(.horizontal, 16)
   .frame(height: 64)
   .background(RoundedRectangle(cornerRadius: 18).fill(C.surface))
  }
  .accessibilityLabel("보낼 코인: \(asset.uppercased()), \(network.rawValue) 네트워크. 바꾸기")
 }

 /// 코인 → 네트워크 고르는 시트 (받기와 같은 화면)
 private var pickerSheet: some View {
  ScrollView(showsIndicators: false) {
   TokenNetworkPicker(
    token: $pickToken,
    title: "무엇을 보낼까요?",
    networkTitle: "어느 네트워크로 보낼까요?",
    networkSub: "받는 분이 알려준 네트워크와 같아야 해요. 다르면 돈을 돌려받기 어려워요.",
    current: TokenItem(network: network, asset: asset),
    ground: C.sheet
   ) { it in
    network = it.network
    asset = it.asset
    picking = false
   }
   .padding(.horizontal, 22)
   .padding(.top, 28)
   .padding(.bottom, 24)
  }
  .presentationDetents([.large])
  .presentationDragIndicator(.visible)
  .presentationBackground(C.sheet)
  .presentationCornerRadius(28)
 }

 private func header(_ title: String, more: String, size: CGFloat = 15) -> some View {
  HStack(alignment: .firstTextBaseline) {
   TX(title, .b, size)
   Spacer()
   Tap(action: { showSent = true }) {
    HStack(spacing: 2) { TX(more, .r, 13, C.sub); Icon("chevron-forward", 13, C.sub) }
     .frame(minHeight: 32)
   }
  }
 }

 // MARK: 확인 · 완료

 // MARK: 0x 네트워크 고르기

 private var networkChips: some View {
  let last = lastSentNet(to, among: detected)
  return VStack(alignment: .leading, spacing: 0) {
   HStack(alignment: .firstTextBaseline) {
    TX("어느 네트워크로 보낼까요?", .b, 15)
    Spacer()
    TX("0x 주소는 셋 다 같아요", .r, 12, C.mute)
   }
   HStack(spacing: 8) {
    ForEach(detected) { n in netChip(n, last: last == n) }
   }
   .padding(.top, 16)
   HStack(alignment: .top, spacing: 10) {
    Icon("warning", 17, C.amber)
    TX("받는 곳이 거래소라면 입금 화면에 적힌 네트워크를 고르세요. 다르면 돈을 잃을 수 있어요.", .r, 13, Color(hex: "#F2D6A6"), lh: 19)
     .fixedSize(horizontal: false, vertical: true)
   }
   .padding(12)
   .frame(maxWidth: .infinity, alignment: .leading)
   .background(RoundedRectangle(cornerRadius: 14).fill(C.amber.opacity(0.10)))
   .padding(.top, 10)
  }
  .padding(.top, 22)
 }

 private func netChip(_ n: WalletNetwork, last: Bool) -> some View {
  let a = assetOn(n)
  let b: Decimal = a.map { balanceOn(n, $0) } ?? 0
  let enabled = a != nil && b > 0
  let selected = netConfirmed && network == n
  let name = n == .avalanche ? "Avalanche" : n.rawValue
  let sub = a == nil ? "이 코인 없음" : (b > 0 ? "잔액 \(NSDecimalNumber(decimal: b).stringValue) \((a ?? "").uppercased())" : "잔액 없음")
  return Tap(disabled: !enabled, action: { pickNet(n) }) {
   VStack(alignment: .leading, spacing: 0) {
    CoinLogo(network: n.rawValue, size: 24)
    Spacer(minLength: 0)
    TX(name, .b, 14, lines: 1)
    TX(sub, .r, 11, enabled ? C.sub : C.faint, lines: 1).padding(.top, 2)
   }
   .padding(.horizontal, 10)
   .padding(.top, 14)
   .padding(.bottom, 10)
   .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .leading)
   .background(RoundedRectangle(cornerRadius: 16).fill(selected ? C.surface2 : C.surface))
   .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? C.text : C.surface3, lineWidth: 1.5))
   .overlay(alignment: .topTrailing) {
    if selected {
     ZStack { Circle().fill(C.text); Icon("checkmark", 12, C.ink) }.frame(width: 20, height: 20).padding(8)
    }
   }
   .overlay(alignment: .topLeading) {
    if last {
     TX("지난번에 보낸 곳", .b, 10, C.ink)
      .padding(.horizontal, 7)
      .frame(height: 20)
      .background(Capsule().fill(C.text))
      .fixedSize()
      .offset(x: 10, y: -10)
    }
   }
   .opacity(enabled ? 1 : 0.5)
  }
  .accessibilityLabel("\(name) 네트워크, \(sub)\(last ? ", 지난번에 보낸 곳" : "")")
  .accessibilityAddTraits(selected ? .isSelected : [])
 }

 private func pickNet(_ n: WalletNetwork) {
  guard let a = assetOn(n) else { return }
  network = n
  asset = a
  netKey = cleanTo.lowercased() + "|" + n.rawValue
  quote = nil; error = ""
 }

 // MARK: 확인 · 완료

 @ViewBuilder private func quoteView(_ quote: TransferQuote) -> some View {
  let st = store.st
  let own = st.ownAccount(address: quote.recipient, net: quote.network.rawValue)
  let who = st.nameOf(quote.recipient, net: quote.network.rawValue)
  let netName = Testnet.on ? Testnet.name(quote.network) : quote.network.rawValue
  let qty = ExactAmount.display(raw: quote.raw, decimals: quote.network.decimals(quote.asset))
  let won = NSDecimalNumber(decimal: qty).doubleValue * st.usdPrice(quote.asset)
  let hint: String = own != nil ? "내 통장끼리 보내요. 받는 통장도 같은 네트워크 주소예요."
   : (who.map { "\($0) 쪽 네트워크도 ‘\(netName)’인지 한 번 더 확인하세요." } ?? "받는 분에게 네트워크가 ‘\(netName)’인지 다시 확인하세요.")
  VStack(alignment: .leading, spacing: 0) {
   TX("보내기 전에 확인해요", .b, 26)

   // 이 네트워크로 보내요 — 가장 크게
   VStack(alignment: .leading, spacing: 0) {
    TX("이 네트워크로 보내요", .sb, 13, C.sub)
    HStack(spacing: 12) {
     CoinLogo(network: quote.network.rawValue, size: 44)
     TX(netName, .b, 28, tracking: -0.5)
    }
    .padding(.top, 10)
    TX(hint, .r, 13, C.sub, lh: 19).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
   }
   .padding(20)
   .frame(maxWidth: .infinity, alignment: .leading)
   .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
   .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(C.surface3, lineWidth: 1))
   .padding(.top, 20)

   VStack(spacing: 4) {
    TX(NSDecimalNumber(decimal: qty).stringValue + " " + quote.asset.uppercased(), .b, 34, tracking: -1)
    TX("약 " + wonOf(won), .r, 15, C.sub)
   }
   .frame(maxWidth: .infinity)
   .padding(.top, 20)

   VStack(alignment: .leading, spacing: 0) {
    HStack(spacing: 6) {
     TX("받는 곳", .r, 14, C.sub)
     Spacer()
     TX(who ?? "모르는 지갑", .sb, 14, lines: 1)
     if let own { MineTag(text: own.active ? "지금 통장" : st.mineTagText(own)) }
    }
    AddressGroups(address: quote.recipient, size: 13).padding(.top, 10)
     .textSelection(.enabled)
    Rectangle().fill(C.line).frame(height: 1).padding(.vertical, 14)
    HStack(alignment: .top) {
     TX("수수료 상한", .r, 14, C.sub)
     Spacer()
     VStack(alignment: .trailing, spacing: 2) {
      TX(NSDecimalNumber(decimal: quote.fee).stringValue + " " + quote.network.native.uppercased(), .sb, 14)
      TX("실제 수수료는 사용한 자원에 따라 달라요", .r, 12, C.mute)
     }
    }
    if quote.asset == "night", let ada = quote.draft["accompanyingADA"] as? String {
     HStack {
      TX("함께 보낼 ADA", .r, 14, C.sub)
      Spacer()
      TX(NSDecimalNumber(decimal: ExactAmount.display(raw: ada, decimals: 6)).stringValue, .sb, 14)
     }
     .padding(.top, 12)
    }
   }
   .padding(16)
   .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
   .padding(.top, 12)

   // 수수료 상한이 지나치게 크면 한 번 더 알려줌 (공개 서버가 비정상 견적을 줄 수도 있어서)
   let feeUSD = NSDecimalNumber(decimal: quote.fee).doubleValue * st.usdPrice(quote.network.native)
   if feeUSD >= 30 || (quote.network.isEVM && won > 0 && feeUSD >= won * 0.5) {
    HStack(alignment: .top, spacing: 10) {
     Icon("warning", 17, C.amber)
     TX("수수료 상한이 약 \(wonOf(feeUSD))로 평소보다 높아요\(won > 0 && feeUSD >= won * 0.5 ? " · 보내는 금액의 절반이 넘어요" : ""). 급하지 않다면 잠시 뒤 다시 확인해주세요.",
        .r, 13, Color(hex: "#F2D6A6"), lh: 19)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 14).fill(C.amber.opacity(0.10)))
    .padding(.top, 12)
   }

   OButton(busy ? "확인 중" : "본인 확인하고 보내기", disabled: busy) { authenticate(quote) }.padding(.top, 18)
   if offerWords { OButton("12단어로 보내기", kind: .secondary, disabled: busy) { askWords = true }.padding(.top, 8) }
   OButton("수정", kind: .secondary, disabled: busy) { self.quote = nil; offerWords = false }.padding(.top, 8)
  }
 }

 @ViewBuilder private func doneView(_ hash: String) -> some View {
  VStack(alignment: .leading, spacing: 12) {
   TX("전송 확인", .b, 26)
   TX("네트워크 확인 중이에요", .sb, 20)
   TX("앱을 다시 열어도 거래 해시로 확인해요", .r, 14, C.sub)
   TX(hash, .r, 12, C.sub).textSelection(.enabled)
   if store.st.nameOf(to, net: network.rawValue) == nil {
    TX("주소록에 저장", .sb, 13, C.sub).padding(.top, 12)
    Field(text: $name, placeholder: "이 주소의 이름 (예: 민수, 업비트)", maxLength: 12)
    OButton("주소록에 저장", kind: .secondary, disabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
     store.saveRecipient(network: network.rawValue, address: to, name: name); toast("주소록에 저장했어요")
    }
   }
   OButton("내역에서 확인") { dismiss(); router.tab = .history }.padding(.top, 8)
  }
 }

 // MARK: 동작

 private func refreshClip() { hasClip = UIPasteboard.general.hasStrings }

 private func applyText(_ text: String) { guard let req = parsePay(text) else { error = "지원하는 지갑 주소 QR이 아니에요"; return }; apply(req) }
 /// 받는 주소와 통장이 안 맞을 때 (테스트넷 ↔ 실제 네트워크)
 private var accountGate: some View {
  HStack(spacing: 12) {
   Icon("flask", 18, needTest ? C.down : C.amber)
   VStack(alignment: .leading, spacing: 2) {
    TX(needTest ? "테스트넷 주소예요" : "실제 네트워크 주소예요", .sb, 14)
    TX(needTest ? "테스트 통장에서만 보낼 수 있어요" : "테스트 통장에서는 보낼 수 없어요", .r, 13, C.sub)
   }
   .frame(maxWidth: .infinity, alignment: .leading)
   Tap(action: {
    if needTest { store.openTestAccount() } else { store.leaveTestAccount() }
    // 바뀐 통장 기준으로 주소 모양을 다시 봄 (tb1 · addr_test 는 테스트넷에서만 읽힘)
    let d = WalletNetwork.detect(to)
    if d.count == 1 { network = d[0] }
    quote = nil; error = ""
   }) {
    TX(needTest ? "테스트 통장으로" : "진짜 통장으로", .b, 13, C.ink)
     .padding(.horizontal, 12)
     .frame(height: 34)
     .background(Capsule().fill(C.text))
     .fixedSize()
   }
  }
  .padding(12)
  .background(RoundedRectangle(cornerRadius: 14).fill(C.surface))
  .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder((needTest ? C.down : C.amber).opacity(0.35), lineWidth: 1))
  .padding(.top, 8)
 }

 private func apply(_ req: PayRequest) {
  reqTo = req.to; testReq = req.test; mainReq = req.mainnet
  to = req.to; quote = nil; error = ""
  if let raw = req.network, let n = WalletNetwork(rawValue: raw) {
   network = n
   if n.isEVM { netKey = req.to.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "|" + n.rawValue }
  }
  if let a = req.asset, network.assets.contains(a) { asset = a }
  // 정확한 수량(ERC-681 최소 단위)이 있으면 그대로, 아니면 달러 요청 금액
  amount = req.qty ?? req.usd.map { String(format: "%.6f", $0) } ?? ""
 }
 private func prepare() {
  guard let owner = store.st.address(net: network.rawValue) else { error = "지갑 주소 검증을 확인해주세요"; return }
  guard !isSelf else { error = "지금 통장의 내 주소예요. 내 주소로는 보낼 수 없어요"; return }
  // 같은 네트워크에 확정 안 된 송금이 있으면 새로 보내지 않음 (나중에 둘 다 처리돼 두 번 나가는 일 방지)
  if let prior = store.st.tx.first(where: { $0.type == .send && $0.inFlight && $0.network == network.rawValue }) {
   error = prior.status == .delayed
    ? "이 네트워크의 이전 송금이 오래 확인되지 않고 있어요. 그 송금이 처리되거나 실패로 확인된 뒤에 보낼 수 있어요"
    : "이 네트워크에서 이전 송금을 확인 중이에요"
   return
  }
  busy = true; error = ""
  let recipient = to.trimmingCharacters(in: .whitespacesAndNewlines), selected = asset, input = amount, selectedNetwork = network
  Task {
   do { let result: TransferQuote
    if selectedNetwork == .tron { result = try await TronTransfer.quote(owner: owner, to: recipient, asset: selected, amount: input) }
    else if selectedNetwork == .solana { result = try await SolanaTransferEngine.quote(owner: owner, to: recipient, asset: selected, amount: input) }
    else if selectedNetwork == .bitcoin { result = try await BitcoinTransfer.quote(owner: owner, to: recipient, amount: input) }
    else if selectedNetwork == .cardano { result = try await CardanoTransfer.quote(owner: owner, to: recipient, asset: selected, amount: input) }
    else { result = try await EVMTransfer.quote(network: selectedNetwork, owner: owner, to: recipient, asset: selected, amount: input) }
    network = result.network; asset = result.asset; quote = result; to = recipient }
   catch { self.error = error.localizedDescription }
   busy = false
  }
 }
 /// 보내기 전 본인 확인 (Keys.sendGate)
 /// - 얼굴 등록 그대로: Face ID 로 Keychain 의 12단어를 꺼내는 것 자체가 확인 (아이폰 암호로는 못 엶)
 /// - 얼굴 등록이 바뀜 · 생체인증 없는 지갑: 앱 비밀번호 먼저
 /// - 그 상태에서 비밀번호를 10번 넘게 틀림: 12단어만
 private func authenticate(_ quoted: TransferQuote) {
  guard !busy else { return }
  error = ""
  let wallet = WalletKeys.active.wallet
  switch WalletKeys.sendGate(wallet: wallet, pinAlways: store.st.pinOnSend) {
  case .faceID:
   unlockAndSend(quoted)
  case .pin:
   pinSub = WalletKeys.isBiometric(wallet) && Biometry.changed() ? "Face ID 등록이 바뀌어서 비밀번호로 한 번 더 확인할게요" : "보내기 전에 비밀번호로 확인할게요"
   askPin = true
  case .words:
   offerWords = true
   error = "비밀번호를 여러 번 틀려서 지금은 12단어로만 보낼 수 있어요"
   askWords = true
  }
 }

 /// Face ID 로 12단어를 꺼내서 보냄 (생체인증 없는 지갑은 앞에서 비밀번호를 확인했고 여기서는 조용히 열림)
 private func unlockAndSend(_ quoted: TransferQuote) {
  busy = true; error = ""
  Task { @MainActor in
   switch await WalletKeys.unlock(wallet: WalletKeys.active.wallet, reason: "\(quoted.asset.uppercased()) 보내기") {
   case .words(let m):
    await send(quoted, mnemonic: m)
   case .cancelled:
    busy = false
   case .failed:
    busy = false
    offerWords = true
    error = "Face ID로 열지 못했어요. Face ID를 쓸 수 없다면 12단어로 보낼 수 있어요"
   }
  }
 }

 /// 서명 → 전파. 12단어는 서명하는 동안만 메모리에 두고 버림
 @MainActor private func send(_ quoted: TransferQuote, mnemonic: String) async {
  defer { busy = false }
  guard active, let wallet = HDWallet(mnemonic: mnemonic, passphrase: "") else { error = "지갑을 열지 못했어요"; return }
  do {
   let signed: SignedTransfer = try WalletKeys.withSigner(wallet) { () throws -> SignedTransfer in
    switch quoted.network {
    case .tron: return try WalletKeys.signTron(quoted)
    case .solana: return try WalletKeys.signSolana(quoted)
    case .bitcoin: return try WalletKeys.signBitcoin(quoted)
    case .cardano: return try WalletKeys.signCardano(quoted)
    default: return try WalletKeys.signEVM(quoted)
    }
   }
   if quoted.network == .solana { try await SolanaTransferEngine.preflight(signed) }
   guard active, store.st.address(net: quoted.network.rawValue) == quoted.owner else { throw TransferError.invalid("현재 지갑을 확인해주세요") }
   store.recordTransfer(quoted, signed: signed)
   hash = signed.id
   offerWords = false
   do {
    try await TransferDispatcher.broadcast(signed, network: quoted.network)
    store.update { state in if let i = state.tx.firstIndex(where: { $0.hash == signed.id && $0.network == quoted.network.rawValue }) { state.tx[i].via = "전파 완료" } }
   }
   catch { self.error = "전파 응답이 불확실해요. 거래 해시로 확인 중이며 다시 보내지 마세요" }
   await store.sync()
  } catch { self.error = error.localizedDescription }
 }
}

// MARK: - 주소록 한 줄

struct RecipientRow: View {
 @EnvironmentObject var store: Store
 let r: SavedRecipient
 var chevron = false

 var body: some View {
  let own = store.st.ownAccount(address: r.address, net: r.network)
  HStack(spacing: 12) {
   Avatar(name: r.name, size: 40, logo: own != nil).networkBadge(r.network, size: 40)
   VStack(alignment: .leading, spacing: 2) {
    HStack(spacing: 6) {
     TX(r.name, .sb, 15, lines: 1)
     if let own { MineTag(text: store.st.mineTagText(own)) }
    }
    (tt(r.network + " · ", .r, 13, C.mute) + addrText(r.address, size: 13, base: C.mute)).lineLimit(1)
   }
   Spacer(minLength: 0)
   if chevron { Icon("chevron-forward", 16, C.mute) }
  }
  .frame(minHeight: 52)
 }
}

// MARK: - 보낸 주소 (최근 보낸 · 저장한 주소록)

struct SentAddressesView: View {
 @EnvironmentObject var store: Store
 @EnvironmentObject var router: Router
 @Environment(\.dismiss) private var dismiss
 let recent: [Tx]
 let onPick: (PayRequest) -> Void
 @State private var adding = false

 var body: some View {
  let saved = Array((store.st.savedRecipients ?? []).reversed())
  OScreen(pad: 24) {
   TX("보낸 주소", .b, 26)
   TX("누르면 보내기 화면에 그대로 채워져요", .r, 15, C.sub).padding(.top, 6)

   TX("최근 보낸", .b, 14, C.sub).padding(.top, 26)
   if recent.isEmpty {
    TX("아직 보낸 주소가 없어요", .r, 14, C.mute).padding(.vertical, 16)
   }
   ForEach(recent) { t in
    Tap(action: { pick(PayRequest(to: t.addr ?? "", network: t.network, asset: t.assetId)) }) {
     HStack(alignment: .top, spacing: 14) {
      CoinLogo(asset: t.assetId, network: t.network, size: 40)
      VStack(alignment: .leading, spacing: 4) {
       HStack(alignment: .firstTextBaseline) {
        TX("\(t.network) · \(t.assetId.uppercased())", .b, 15, lines: 1)
        Spacer(minLength: 8)
        TX(dayLabel(t.ts), .r, 12, C.mute, lines: 1)
       }
       // 보낸 주소는 전체를 보여줌 (앞6·뒤6 강조)
       AddrText(addr: t.addr ?? "", full: true, size: 13)
      }
     }
     .padding(.vertical, 14)
     .overlay(alignment: .bottom) { Rectangle().fill(C.surface2).frame(height: 1) }
    }
   }

   HStack {
    TX("저장한 주소록", .b, 14, C.sub)
    Spacer()
    Tap(action: { adding = true }) {
     HStack(spacing: 4) { Icon("add", 14, C.text); TX("새 주소", .sb, 13) }
      .padding(.horizontal, 12)
      .frame(height: 32)
      .background(Capsule().fill(C.surface2))
    }
   }
   .padding(.top, 28)
   if saved.isEmpty {
    TX("자주 보내는 주소에 이름을 붙여두면 편해요", .r, 14, C.mute).padding(.vertical, 16)
   }
   ForEach(saved) { r in
    Tap(action: { pick(PayRequest(to: r.address, network: r.network)) }) {
     RecipientRow(r: r).padding(.vertical, 6)
    }
    .contextMenu {
     Button(role: .destructive) {
      store.update { $0.savedRecipients?.removeAll { $0.id == r.id } }
     } label: { Label("주소록에서 삭제", systemImage: "trash") }
    }
   }
  }
  .sheet(isPresented: $adding) {
   ContactEditView(onDone: { adding = false }).environmentObject(store).environmentObject(router)
  }
 }

 private func pick(_ req: PayRequest) { onPick(req); dismiss() }
}

// MARK: - 주소록 상세

struct SavedRecipientDetailView: View {
 @EnvironmentObject var store: Store
 @EnvironmentObject var router: Router
 @Environment(\.dismiss) private var dismiss
 let recipient: SavedRecipient
 @State private var editedName = ""
 @State private var askDelete = false

 private var currentName: String {
  (store.st.savedRecipients ?? []).first(where: { $0.id == recipient.id })?.name ?? recipient.name
 }

 var body: some View {
  let n = WalletNetwork(rawValue: recipient.network)
  let txs = store.st.tx.filter { $0.network == recipient.network && $0.addr == recipient.address }
  OScreen(pad: 24) {
   HStack(spacing: 14) {
    Avatar(name: currentName, size: 56, logo: store.st.ownAccount(address: recipient.address, net: recipient.network) != nil).networkBadge(recipient.network, size: 56)
    VStack(alignment: .leading, spacing: 3) {
     TX(currentName, .b, 24, lines: 1)
     TX("\(recipient.network) 네트워크" + (n.map { " · " + $0.assets.map { $0.uppercased() }.joined(separator: " · ") } ?? ""), .r, 13, C.sub, lines: 1)
    }
   }

   VStack(alignment: .leading, spacing: 6) {
    TX("지갑 주소", .sb, 12, C.mute)
    AddressGroups(address: recipient.address, size: 16)
    HStack {
     Spacer()
     Tap(action: { UIPasteboard.general.string = recipient.address; haptic(.success); toast("주소를 복사했어요") }) {
      HStack(spacing: 6) { Icon("copy-outline", 15, C.text); TX("주소 복사", .sb, 13) }
       .padding(.horizontal, 12)
       .frame(height: 36)
       .background(Capsule().fill(C.surface3))
     }
    }
    .padding(.top, 4)
   }
   .padding(.horizontal, 16)
   .padding(.vertical, 14)
   .frame(maxWidth: .infinity, alignment: .leading)
   .background(RoundedRectangle(cornerRadius: 16).fill(C.surface))
   .padding(.top, 24)

   TX("이름", .sb, 13, C.sub).padding(.top, 20)
   Field(text: $editedName, placeholder: "이름", maxLength: 12)
    .padding(.top, 6)
    .onSubmit(saveName)
   TX("입력을 마치면 바로 저장돼요", .r, 12, C.mute).padding(.top, 6)

   OButton("이 주소로 보내기") {
    saveName()
    router.send(PayRequest(to: recipient.address, network: recipient.network))
   }
   .padding(.top, 22)

   TX("이 주소와의 거래", .b, 14, C.sub).padding(.top, 28)
   if txs.isEmpty {
    TX("아직 주고받은 적이 없어요", .r, 14, C.mute).padding(.vertical, 16)
   }
   ForEach(txs) { tx in TxRow(t: tx) { router.push(.txDetail(tx.id)) } }

   Button { askDelete = true } label: {
    TX("주소록에서 삭제", .m, 15, C.red).frame(maxWidth: .infinity).frame(height: 44)
   }
   .buttonStyle(.plain)
   .padding(.top, 16)
  }
  .onAppear { editedName = currentName }
  .onDisappear(perform: saveName)
  .confirmationDialog("\(currentName)을(를) 주소록에서 지울까요?", isPresented: $askDelete, titleVisibility: .visible) {
   Button("지우기", role: .destructive) {
    store.update { $0.savedRecipients?.removeAll { $0.id == recipient.id } }
    dismiss()
   }
  } message: { Text("주고받은 내역은 그대로 남아요") }
 }

 private func saveName() {
  let v = editedName.trimmingCharacters(in: .whitespaces)
  guard !v.isEmpty, v != currentName,
        (store.st.savedRecipients ?? []).contains(where: { $0.id == recipient.id }) else { return }
  store.saveRecipient(network: recipient.network, address: recipient.address, name: v)
  toast("이름을 저장했어요")
 }
}
