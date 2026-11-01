import SwiftUI

// 테스트 토큰 받기 — 테스트 통장에서만
// 솔라나 SOL 은 앱 안에서 바로(devnet 에어드롭), 나머지는 주소를 복사하고 각 네트워크의 받기 사이트를 엶

struct FaucetView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    @State private var dropping = false

    private let order: [WalletNetwork] = [.solana, .ethereum, .avalanche, .mantle, .tron, .bitcoin, .cardano]

    var body: some View {
        let st = store.st
        OScreen {
            TX("테스트 토큰 받기", .b, 26)
            TX("테스트넷 토큰은 실제 가치가 없어요. 받기·보내기를 마음껏 연습해보세요.", .r, 15, C.sub, lh: 22)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if !st.inTest {
                VStack(alignment: .leading, spacing: 12) {
                    TX("테스트 통장에서 받을 수 있어요", .sb, 15)
                    OButton("테스트 통장으로 바꾸기", md: true) { store.openTestAccount() }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(C.surface))
                .padding(.top, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(order) { n in row(n, last: n == order.last) }
                }
                .background(RoundedRectangle(cornerRadius: 20).fill(C.surface))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.top, 20)

                TX("사이트 버튼을 누르면 내 주소가 복사돼요. 사이트의 주소 칸에 붙여넣고 받으면, 몇 분 안에 이 통장 잔액에 들어와요.",
                   .r, 13, C.mute, lh: 19)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    private func row(_ n: WalletNetwork, last: Bool) -> some View {
        let addr = store.st.address(net: n.rawValue) ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CoinLogo(network: n.rawValue, size: 36, ring: C.surface)
                VStack(alignment: .leading, spacing: 2) {
                    TX(Testnet.name(n), .sb, 16)
                    if addr.isEmpty {
                        TX("주소를 확인하지 못했어요", .r, 13, C.red)
                    } else {
                        AddrText(addr: addr, size: 13, base: C.mute)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                ForEach(Testnet.faucets(n)) { f in
                    Tap(disabled: addr.isEmpty || (f.url == nil && dropping), action: { get(f, n, addr) }) {
                        HStack(spacing: 4) {
                            if f.url == nil && dropping {
                                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14).tint(C.ink)
                            }
                            TX(f.label, .sb, 13, f.url == nil ? C.ink : C.text)
                            if f.url != nil { Icon("open-outline", 12, C.sub) }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(f.url == nil ? C.text : C.surface3))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 48)
        }
        .padding(16)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(C.line).frame(height: 1) } }
    }

    private func get(_ f: Testnet.Faucet, _ n: WalletNetwork, _ addr: String) {
        guard let url = f.url else { airdrop(addr); return }
        UIPasteboard.general.string = addr
        haptic(.success)
        toast("\(Testnet.name(n)) 주소를 복사했어요 · 사이트에 붙여넣어 주세요", "copy-outline")
        after(0.6) { openURL(url) }
    }

    private func airdrop(_ addr: String) {
        dropping = true
        Task {
            do {
                _ = try await Testnet.airdrop(addr)
                await MainActor.run {
                    dropping = false
                    haptic(.success)
                    toast("테스트 SOL 1개를 요청했어요 · 곧 들어와요", "checkmark-circle")
                }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await store.sync()
            } catch {
                await MainActor.run {
                    dropping = false
                    haptic(.error)
                    toast(error.localizedDescription, "alert-circle")
                }
            }
        }
    }
}

/// "테스트넷" 작은 표시
struct TestnetChip: View {
    var text = "테스트넷"
    var body: some View {
        HStack(spacing: 4) {
            Icon("flask", 12, C.down)
            TX(text, .sb, 12, C.down)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(C.down.opacity(0.16)))
        .fixedSize()
    }
}

/// 홈 · 테스트 통장 안내 (테스트 통장일 때만)
struct TestnetBanner: View {
    let onFaucet: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ZStack { Circle().fill(C.down.opacity(0.16)); Icon("flask", 18, C.down) }
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                TX("테스트넷 통장이에요", .sb, 15)
                TX("실제 돈이 아니에요 · 금액은 참고용", .r, 13, C.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Tap(action: onFaucet) {
                TX("토큰 받기", .b, 13, C.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Capsule().fill(C.text))
                    .fixedSize()
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(C.surface))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(C.down.opacity(0.35), lineWidth: 1))
        .padding(.bottom, 12)
    }
}
