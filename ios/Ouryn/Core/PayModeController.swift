import Foundation
import ActivityKit

// 결제 모드 켜고 끄기 (Live Activity)
enum PayMode {
    /// 설정에서 '실시간 현황'이 꺼져 있으면 false
    static var allowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static var isOn: Bool {
        Activity<PayModeAttributes>.activities.contains { $0.activityState == .active }
    }

    static var endsAt: Date? {
        Activity<PayModeAttributes>.activities.first { $0.activityState == .active }?.content.state.endsAt
    }

    @discardableResult
    static func start() -> Bool {
        stop()
        let end = Date().addingTimeInterval(PayModeTiming.duration)
        let content = ActivityContent(state: PayModeAttributes.ContentState(endsAt: end), staleDate: end)
        do {
            _ = try Activity<PayModeAttributes>.request(attributes: PayModeAttributes(), content: content, pushType: nil)
            return true
        } catch {
            return false
        }
    }

    static func stop() {
        for a in Activity<PayModeAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
