import SwiftUI
import UIKit
import CoreText

// MARK: - 색 (src/theme.js 그대로)

extension Color {
    /// "#RRGGBB" 또는 "rgba(r,g,b,a)"
    init(hex css: String) {
        let s = css.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("rgba") {
            let inner = s.drop(while: { $0 != "(" }).dropFirst().prefix(while: { $0 != ")" })
            let parts = inner.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            let r = parts.count > 0 ? parts[0] : 0
            let g = parts.count > 1 ? parts[1] : 0
            let b = parts.count > 2 ? parts[2] : 0
            let a = parts.count > 3 ? parts[3] : 1
            self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
            return
        }
        var hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

enum C {
    static let bg = Color(hex: "#0B0B0D")
    static let surface = Color(hex: "#17171A")
    static let surface2 = Color(hex: "#1F1F23")
    static let surface3 = Color(hex: "#2A2A30")
    static let line = Color(hex: "#232328")
    static let text = Color(hex: "#F7F7F9")
    static let sub = Color(hex: "#A0A0AA")
    // 작은 글씨용: 배경·카드 모두에서 명도 대비 4.5:1 이상 (#6B6B76 은 3.1~3.7:1)
    static let mute = Color(hex: "#8A8A94")
    static let faint = Color(hex: "#3A3A42")
    // 포인트 컬러: 파랑 대신 실버 (키 이름은 호환용으로 유지)
    static let blue = Color(hex: "#D4D4D8")
    static let blueSoft = Color(hex: "rgba(230,230,236,0.08)")
    static let blueText = Color(hex: "#E4E4E7")
    static let ink = Color(hex: "#0E0E10") // 메탈 위 글자색
    static let up = Color(hex: "#FF6464") // 가격 오름 (국내 관례: 빨강)
    static let down = Color(hex: "#5B8CFF") // 가격 내림 (국내 관례: 파랑)
    static let green = Color(hex: "#00C896")
    static let greenSoft = Color(hex: "rgba(0,200,150,0.12)")
    static let red = Color(hex: "#FF5C5C")
    static let redSoft = Color(hex: "rgba(255,92,92,0.12)")
    // 진행 중·늦어짐 (완료=초록, 실패=빨강과 구분)
    static let amber = Color(hex: "#F5A524")
    static let amberSoft = Color(hex: "rgba(245,165,36,0.12)")
    static let sheet = Color(hex: "#1A1A1E")
    // 지갑 주소 앞 6 · 뒤 6 자리
    static let addr = Color(hex: "#7CC4FF")
}

// 포인트 면: 거의 단색인 오프화이트 (아주 약한 위→아래 음영만)
enum METAL {
    static let colors = [Color(hex: "#F7F7F9"), Color(hex: "#E9E9EC")]
}
enum EDGE {
    static let colors = [Color(hex: "rgba(255,255,255,0.06)"), Color(hex: "rgba(255,255,255,0.015)"), Color(hex: "rgba(255,255,255,0.02)")]
}
enum SWITCH {
    static let on = Color(hex: "#8E8E96")
    static let off = Color(hex: "#2A2A30")
}

// MARK: - 글꼴 (Pretendard)

enum W {
    case r, m, sb, b
    var name: String {
        switch self {
        case .r: return "Pretendard-Regular"
        case .m: return "Pretendard-Medium"
        case .sb: return "Pretendard-SemiBold"
        case .b: return "Pretendard-Bold"
        }
    }
}

func pfont(_ w: W, _ size: CGFloat) -> Font {
    .custom(w.name, fixedSize: size)
}

func uiFont(_ w: W, _ size: CGFloat) -> UIFont {
    UIFont(name: w.name, size: size) ?? .systemFont(ofSize: size)
}

enum Fonts {
    /// 번들에 넣은 글꼴 등록 (Info.plist 없이)
    static func register() {
        let names = ["Pretendard-Regular", "Pretendard-Medium", "Pretendard-SemiBold", "Pretendard-Bold"]
        for n in names {
            if let url = Bundle.main.url(forResource: n, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        if let url = Bundle.main.url(forResource: "Ionicons", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - React Native Easing 대응

enum Ease {
    static func outCubic(_ d: Double) -> Animation { .timingCurve(0.215, 0.61, 0.355, 1, duration: d) }
    static func inOutCubic(_ d: Double) -> Animation { .timingCurve(0.645, 0.045, 0.355, 1, duration: d) }
    static func outQuad(_ d: Double) -> Animation { .timingCurve(0.25, 0.46, 0.45, 0.94, duration: d) }
    static func inOutQuad(_ d: Double) -> Animation { .timingCurve(0.455, 0.03, 0.515, 0.955, duration: d) }
    static func inOutSin(_ d: Double) -> Animation { .timingCurve(0.445, 0.05, 0.55, 0.95, duration: d) }
    /// Animated.timing 기본값 (Easing.inOut(Easing.ease))
    static func standard(_ d: Double) -> Animation { .timingCurve(0.42, 0, 0.58, 1, duration: d) }
    /// Animated.spring(friction, tension) → stiffness/damping
    static func rnSpring(friction: Double, tension: Double) -> Animation {
        .interpolatingSpring(stiffness: (tension - 30) * 3.62 + 194, damping: (friction - 8) * 3 + 25)
    }
}

/// 곡선 함수 (시간 기반 애니메이션용)
enum Curve {
    static func outCubic(_ t: Double) -> Double { let u = 1 - t; return 1 - u * u * u }
    static func inOutCubic(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
    static func outQuad(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }
    static func inQuad(_ t: Double) -> Double { t * t }
    static func clamp(_ t: Double) -> Double { min(1, max(0, t)) }
    /// RN friction/tension 스프링의 0→1 응답
    static func spring(_ t: Double, friction: Double = 4, tension: Double = 160) -> Double {
        if t <= 0 { return 0 }
        let k = (tension - 30) * 3.62 + 194
        let c = (friction - 8) * 3 + 25
        let w0 = sqrt(k)
        let z = c / (2 * w0)
        if z < 1 {
            let wd = w0 * sqrt(1 - z * z)
            return 1 - exp(-z * w0 * t) * (cos(wd * t) + (z * w0 / wd) * sin(wd * t))
        }
        return 1 - exp(-w0 * t) * (1 + w0 * t)
    }
}

// MARK: - 안전 영역

enum Insets {
    static var window: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ??
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
    }
    static var top: CGFloat { window?.safeAreaInsets.top ?? 47 }
    static var bottom: CGFloat { window?.safeAreaInsets.bottom ?? 34 }
    /// RN: paddingBottom = max(insets.bottom, 16) 를 안전 영역 안에서 맞춘 값
    static var footerExtra: CGFloat { max(0, 16 - bottom) }
}

// MARK: - 진동

enum Haptic {
    case light, medium, select, success, error
}

func haptic(_ kind: Haptic = .light) {
    switch kind {
    case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
    case .select: UISelectionFeedbackGenerator().selectionChanged()
    case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// setTimeout
func after(_ seconds: Double, _ fn: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: fn)
}

/// 애니메이션 없이 상태 바꾸기
func noAnim(_ fn: () -> Void) {
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t, fn)
}
