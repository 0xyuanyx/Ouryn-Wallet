import SwiftUI
import ActivityKit
import AppIntents

// 앱과 위젯(OurynWidgets)이 같이 쓰는 코드 — 두 타깃 모두에 들어감
// 여기서는 앱 전용 코드(C, Color(hex:) 등)를 쓰면 안 됨

/// 결제 모드: 켜면 최대 8시간 다이나믹 아일랜드·잠금 화면에 로고가 떠 있고, 누르면 바로 QR 찍기
/// (Live Activity 는 시작·끝이 있는 작업에만 쓰라는 애플 규칙 → '결제 모드'라는 작업으로 정의)
struct PayModeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
    }
}

enum PayModeTiming {
    /// 시스템이 다이나믹 아일랜드에서 내리는 한도와 같음
    static let duration: TimeInterval = 8 * 3600
}

/// 앱 바로가기 주소 (다이나믹 아일랜드·잠금 화면에서 누를 때)
enum OurynLink {
    static let scan = URL(string: "ouryn://scan")!
    static let receive = URL(string: "ouryn://receive")!
}

/// 앱이 열리면 갈 화면 — 제어 센터 버튼(인텐트)과 주소 모두 여기로 모임
enum PendingLink {
    static let key = "ouryn.pendingLink"
    static func set(_ v: String) {
        UserDefaults.standard.set(v, forKey: key)
        NotificationCenter.default.post(name: .ourynLink, object: v)
    }
    static func take() -> String? {
        let v = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        return v
    }
}

extension Notification.Name {
    static let ourynLink = Notification.Name("ouryn.link")
}

/// 앱에서 바로 열 화면 (제어 센터 버튼이 고름)
enum OurynScreen: String, AppEnum {
    case scan
    case receive

    static var typeDisplayRepresentation = TypeDisplayRepresentation("Ouryn 화면")
    static var caseDisplayRepresentations: [OurynScreen: DisplayRepresentation] = [
        .scan: DisplayRepresentation("QR 찍기"),
        .receive: DisplayRepresentation("내 QR"),
    ]
}

/// 'Ouryn 결제' — 제어 센터·잠금 화면·동작 버튼에서 누르면 앱이 열리며 바로 QR 찍기
/// 실기기에서 앱이 확실히 열리게: OpenIntent + 앱·위젯 두 타깃 모두에 들어 있어야 함 (이 파일이 Shared 에 있는 이유)
/// (일반 AppIntent + openAppWhenRun, 위젯에서 ouryn:// 주소 열기는 실기기에서 앱이 안 열림)
struct OpenScanIntent: OpenIntent {
    static var title: LocalizedStringResource = "Ouryn 결제"
    static var description = IntentDescription("QR 찍기 화면을 바로 열어요")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "화면")
    var target: OurynScreen

    init() {}
    init(target: OurynScreen) { self.target = target }

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingLink.set(target.rawValue)
        return .result()
    }
}

/// 브랜드 심볼 (assets/brand/ouryn-symbol.svg) — 위젯에서도 그릴 수 있게 Shape 로만 구성
/// SVG 와 같은 320 좌표: 호 M199.9 66.1 A102 102 0 1 0 262 160 (굵기 40, 둥근 끝) + 점 (248,102) r20
struct OurynMark: View {
    var size: CGFloat = 24
    var mono: Color? = nil

    private static let silver = Gradient(stops: [
        .init(color: Color(red: 0.988, green: 0.988, blue: 0.988), location: 0),
        .init(color: Color(red: 0.776, green: 0.776, blue: 0.784), location: 0.16),
        .init(color: .white, location: 0.34),
        .init(color: Color(red: 0.902, green: 0.902, blue: 0.906), location: 0.58),
        .init(color: Color(red: 0.651, green: 0.651, blue: 0.667), location: 0.81),
        .init(color: Color(red: 0.957, green: 0.957, blue: 0.961), location: 1),
    ])
    private static let dot = Gradient(stops: [
        .init(color: .white, location: 0),
        .init(color: Color(red: 0.969, green: 0.969, blue: 0.973), location: 0.42),
        .init(color: Color(red: 0.725, green: 0.725, blue: 0.741), location: 1),
    ])

    var body: some View {
        let k = size / 320
        ZStack(alignment: .topLeading) {
            MarkArc()
                .stroke(mono.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient(gradient: Self.silver,
                                                     startPoint: UnitPoint(x: 76.0 / 320, y: 54.0 / 320),
                                                     endPoint: UnitPoint(x: 255.0 / 320, y: 265.0 / 320))),
                        style: StrokeStyle(lineWidth: 40 * k, lineCap: .round))
            Circle()
                .fill(mono.map { AnyShapeStyle($0) } ?? AnyShapeStyle(RadialGradient(gradient: Self.dot,
                                                   center: UnitPoint(x: 0.33, y: 0.28),
                                                   startRadius: 0, endRadius: 40 * k * 0.78)))
                .frame(width: 40 * k, height: 40 * k)
                .offset(x: 228 * k, y: 82 * k)
        }
        .frame(width: size, height: size)
    }
}

/// 열린 원 (반지름 102, 약 293도)
private struct MarkArc: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 320
        let a0 = atan2(66.1 - 160.0, 199.9 - 160.0)
        return Path { p in
            p.addArc(center: CGPoint(x: 160 * k, y: 160 * k), radius: 102 * k,
                     startAngle: .radians(a0), endAngle: .radians(0), clockwise: true)
        }
    }
}
