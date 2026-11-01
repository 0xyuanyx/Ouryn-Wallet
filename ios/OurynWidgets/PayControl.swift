import SwiftUI
import WidgetKit
import AppIntents

// 'Ouryn 결제' 버튼 — 제어 센터 · 잠금 화면 아래 버튼 · 동작 버튼(아이폰 15 Pro 이상)에 둘 수 있음
// 누르면 앱이 열리면서 바로 QR 찍기 (결제 모드를 안 켜도 언제든)
struct PayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.yuanyx.ouryn.pay") {
            ControlWidgetButton(action: OpenScanIntent(target: .scan)) {
                Label("Ouryn 결제", systemImage: "qrcode.viewfinder")
            }
        }
        .displayName("Ouryn 결제")
        .description("누르면 바로 QR을 찍어요")
    }
}
