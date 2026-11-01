import SwiftUI
import WidgetKit

// 위젯 확장: 결제 모드(다이나믹 아일랜드·잠금 화면) + 'Ouryn 결제' 버튼(제어 센터·잠금 화면·동작 버튼)
@main
struct OurynWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PayModeLiveActivity()
        PayControl()
    }
}
