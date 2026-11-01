import SwiftUI
import WidgetKit
import ActivityKit

// 결제 모드 — 음악 앨범처럼 다이나믹 아일랜드 왼쪽에 로고가 작게 떠 있음
// 어디를 눌러도 앱이 열리면서 바로 QR 찍기 화면 (ouryn://scan)
// 길게 누르면 펼쳐져서 'QR 찍기' / '내 QR' 두 버튼

private let INK = Color(red: 0.043, green: 0.043, blue: 0.051)   // #0B0B0D
private let SUB = Color(red: 0.627, green: 0.627, blue: 0.667)   // #A0A0AA

struct PayModeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PayModeAttributes.self) { context in
            // 잠금 화면 (다이나믹 아일랜드가 없는 폰도 여기서 보임)
            HStack(spacing: 14) {
                ZStack { Circle().fill(Color.black); OurynMark(size: 30) }
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("결제 모드").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text("\(endText(context.state.endsAt))까지 · 누르면 바로 QR").font(.system(size: 13)).foregroundStyle(SUB)
                }
                Spacer(minLength: 0)
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(16)
            .activityBackgroundTint(INK)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(OurynLink.scan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    OurynMark(size: 34).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(endText(context.state.endsAt))까지")
                        .font(.system(size: 12))
                        .foregroundStyle(SUB)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("결제 모드").font(.system(size: 15, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Link(destination: OurynLink.scan) {
                            Label("QR 찍기", systemImage: "qrcode.viewfinder")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(INK)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Capsule().fill(Color.white))
                        }
                        Link(destination: OurynLink.receive) {
                            Label("내 QR", systemImage: "qrcode")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                        }
                    }
                    .padding(.top, 6)
                }
            } compactLeading: {
                OurynMark(size: 22)
            } compactTrailing: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            } minimal: {
                OurynMark(size: 20)
            }
            .widgetURL(OurynLink.scan)
            .keylineTint(.white)
        }
    }
}

/// "오후 10:15"
private func endText(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = "a h:mm"
    return f.string(from: d)
}
