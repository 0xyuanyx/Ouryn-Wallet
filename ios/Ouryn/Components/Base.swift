import SwiftUI

// src/components/base.js + Metal.js

// MARK: - Tap: 누르면 살짝 작아지는 공통 터치 영역

struct TapStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.18, dampingFraction: 1), value: configuration.isPressed)
    }
}

struct Tap<Content: View>: View {
    var scale: CGFloat = 0.97
    var haptics: Haptic? = nil
    var disabled = false
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button {
            if let h = haptics { haptic(h) }
            action()
        } label: {
            content().contentShape(Rectangle())
        }
        .buttonStyle(TapStyle(scale: scale))
        .disabled(disabled)
    }
}

// MARK: - Edge: 가장자리에 빛이 살짝 도는 면

extension View {
    func edge(_ radius: CGFloat = 24, _ bg: Color, border: Color? = nil) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius).fill(bg))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        LinearGradient(stops: [
                            .init(color: EDGE.colors[0], location: 0),
                            .init(color: EDGE.colors[1], location: 0.5),
                            .init(color: EDGE.colors[2], location: 1),
                        ], startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 0.4, y: 1)),
                        lineWidth: 1)
            )
            .overlay(
                Group {
                    if let b = border {
                        RoundedRectangle(cornerRadius: radius - 1).strokeBorder(b, lineWidth: 1).padding(1)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// 실버 면 (diagonal = MetalFill, vertical = Button/Pill)
func metalGradient(vertical: Bool = false) -> LinearGradient {
    LinearGradient(colors: METAL.colors, startPoint: .topLeading, endPoint: vertical ? .bottom : .bottomTrailing)
}

/// 실버 원 안의 아이콘/글자
struct MetalBadge: View {
    var icon: String? = nil
    var label: String? = nil
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(metalGradient())
            if let i = icon {
                Icon(i, size * 0.46, C.ink)
            } else {
                TX(label ?? "", .b, size * 0.42, C.ink)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Button

enum BKind { case primary, secondary, danger, ghost }

struct OButton: View {
    let title: String
    var kind: BKind = .primary
    var md = false
    var icon: String? = nil
    var disabled = false
    var loading = false
    var expand = true
    var hpad: CGFloat = 16
    let action: () -> Void

    init(_ title: String, kind: BKind = .primary, md: Bool = false, icon: String? = nil, disabled: Bool = false,
         loading: Bool = false, expand: Bool = true, hpad: CGFloat = 16, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.md = md
        self.icon = icon
        self.disabled = disabled
        self.loading = loading
        self.expand = expand
        self.hpad = hpad
        self.action = action
    }

    private var r: CGFloat { md ? 12 : 16 }
    private var h: CGFloat { md ? 44 : 56 }
    private var fg: Color {
        switch kind {
        case .primary: return C.ink
        case .danger: return C.red
        case .ghost: return C.sub
        case .secondary: return C.text
        }
    }

    @ViewBuilder private var bg: some View {
        switch kind {
        case .primary: metalGradient(vertical: true)
        case .danger: C.redSoft
        case .ghost: Color.clear
        case .secondary: C.surface2
        }
    }

    var body: some View {
        Tap(haptics: .light, disabled: disabled || loading, action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView().tint(fg)
                } else {
                    if let i = icon { Icon(i, md ? 17 : 19, fg) }
                    TX(title, .sb, md ? 15 : 17, fg, lines: 1)
                }
            }
            .padding(.horizontal, hpad)
            .frame(maxWidth: expand ? .infinity : nil)
            .frame(height: h)
            .background(bg)
            .overlay(
                Group {
                    if kind == .secondary {
                        RoundedRectangle(cornerRadius: r)
                            .strokeBorder(LinearGradient(stops: [
                                .init(color: EDGE.colors[0], location: 0),
                                .init(color: EDGE.colors[1], location: 0.5),
                                .init(color: EDGE.colors[2], location: 1),
                            ], startPoint: .topLeading, endPoint: UnitPoint(x: 0.3, y: 1)), lineWidth: 1)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: r))
        }
        .opacity(disabled ? 0.3 : 1)
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    var top: CGFloat = 20
    var bottom: CGFloat = 20
    var horizontal: CGFloat = 20
    var bg: Color = C.surface
    var border: Color? = nil
    var onPress: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.top, top)
            .padding(.bottom, bottom)
            .padding(.horizontal, horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .edge(24, bg, border: border)
        Group {
            if let p = onPress {
                Tap(scale: 0.985, action: p) { inner }
            } else {
                inner
            }
        }
        .padding(.bottom, 12)
    }
}

// MARK: - SectionTitle

struct SectionTitle: View {
    let title: String
    var right: String? = nil
    var onRight: (() -> Void)? = nil
    var bottom: CGFloat = 6

    var body: some View {
        HStack {
            TX(title, .b, 18)
            Spacer()
            if let r = right {
                Button { onRight?() } label: {
                    HStack(spacing: 0) {
                        TX(r, .r, 14, C.mute)
                        Icon("chevron-forward", 14, C.mute)
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-10)
            }
        }
        .padding(.bottom, bottom)
    }
}

// MARK: - Avatar

struct Avatar: View {
    var name: String? = nil
    var icon: String? = nil
    var color: Color? = nil
    var size: CGFloat = 44
    var iconColor: Color = .white
    var ring = false
    /// 내 통장 — 글자 대신 Ouryn 로고 (원 안 비율은 하단 O 버튼과 같게)
    var logo = false

    var body: some View {
        ZStack {
            if logo {
                Circle().fill(C.surface)
                Circle().strokeBorder(C.surface3, lineWidth: 1)
                Logo(size: size * LOGO_IN_CIRCLE)
            } else if color != nil || icon != nil {
                Circle().fill(color ?? C.surface3)
                if let i = icon {
                    Icon(i, size * 0.45, iconColor)
                } else {
                    TX(initial, .b, size * 0.38, .white)
                }
            } else {
                // 사람: 차분한 회색 원
                Circle().fill(C.surface3)
                TX(initial, .b, size * 0.38, Color(hex: "#E9E9EC"))
            }
        }
        .frame(width: size, height: size)
        .overlay(Group { if ring { Circle().strokeBorder(C.bg, lineWidth: 2) } })
    }

    private var initial: String {
        if let n = name, let f = n.first { return String(f) }
        return "?"
    }
}

struct AvatarSpec {
    var name: String? = nil
    var icon: String? = nil
    var color: Color? = nil
    var iconColor: Color = .white
    var logo = false

    func view(_ size: CGFloat = 44) -> Avatar {
        Avatar(name: name, icon: icon, color: color, size: size, iconColor: iconColor, logo: logo)
    }
}

/// 이름이 있으면 사람, 없으면 물음표
func personAvatar(_ name: String?, _ size: CGFloat = 44, unknownIcon: String = "help") -> Avatar {
    if let n = name { return Avatar(name: n, size: size) }
    return Avatar(icon: unknownIcon, color: C.surface3, size: size)
}

// MARK: - ListItem

struct ListItem: View {
    var left: AnyView
    var title: String
    var titleRight: AnyView? = nil
    var sub: String? = nil
    var subColor: Color? = nil
    var right: String? = nil
    var rightSub: String? = nil
    var rightSubColor: Color? = nil
    var rightColor: Color? = nil
    var rightNode: AnyView? = nil
    var chevron = false
    var dim = false
    var onPress: (() -> Void)? = nil

    var row: some View {
        HStack(spacing: 14) {
            left
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    TX(title, .sb, 16, lines: 1)
                    if let tr = titleRight { tr }
                }
                if let s = sub, !s.isEmpty {
                    TX(s, .r, 13, subColor ?? C.mute, lines: 1).padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let r = right {
                VStack(alignment: .trailing, spacing: 0) {
                    TX(r, .sb, 16, rightColor ?? C.text, lines: 1)
                    if let rs = rightSub {
                        TX(rs, rightSubColor != nil ? .m : .r, 13, rightSubColor ?? C.mute).padding(.top, 3)
                    }
                }
                .fixedSize()
            }
            if let rn = rightNode { rn }
            if chevron { Icon("chevron-forward", 18, C.faint) }
        }
        .padding(.vertical, 12)
        .opacity(dim ? 0.45 : 1)
    }

    var body: some View {
        if let p = onPress {
            Tap(scale: 0.98, action: p) { row }
        } else {
            row
        }
    }
}

// MARK: - Chip / Pill / Divider

struct Chip: View {
    let label: String
    var soon = false
    var color: Color? = nil
    var bg: Color? = nil

    var body: some View {
        TX(label, .sb, 11, color ?? (soon ? C.blueText : C.sub))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(bg ?? (soon ? C.blueSoft : C.surface3)))
    }
}

struct Pill: View {
    let label: String
    let active: Bool
    let onPress: () -> Void

    var body: some View {
        Tap(haptics: .select, action: onPress) {
            TX(label, .sb, 14, active ? C.ink : C.sub)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(
                    Group {
                        if active { metalGradient(vertical: true) } else { C.surface2 }
                    }
                )
                .clipShape(Capsule())
        }
    }
}

struct Divider1: View {
    var body: some View { Rectangle().fill(C.line).frame(height: 1) }
}

// MARK: - InfoRow

struct InfoRow: View {
    let label: String
    var value: String? = nil
    var valueColor: Color? = nil
    var right: AnyView? = nil
    var last = false
    var onPress: (() -> Void)? = nil

    var row: some View {
        HStack(spacing: 16) {
            TX(label, .r, 15, C.sub)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let v = value {
                    TX(v, .m, 15, valueColor ?? C.text, align: .trailing)
                }
                if let r = right { r }
            }
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(C.line).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }

    var body: some View {
        if let p = onPress {
            Button(action: p) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

// MARK: - Empty

struct Empty: View {
    var icon = "file-tray-outline"
    let title: String
    var sub: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Icon(icon, 36, C.faint)
            TX(title, .sb, 16, C.sub)
            if let s = sub {
                TX(s, .r, 14, C.mute, lh: 20, align: .center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 스위치 (RN Switch 색 그대로)

struct OSwitch: View {
    @Binding var isOn: Bool
    var onChange: ((Bool) -> Void)? = nil

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? SWITCH.on : SWITCH.off)
            Circle().fill(Color.white).frame(width: 27, height: 27).padding(2)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .frame(width: 51, height: 31)
        .contentShape(Capsule())
        .onTapGesture {
            let v = !isOn
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { isOn = v }
            onChange?(v)
        }
    }
}

// MARK: - 입력칸 (Onboarding.js 의 Field)

struct Field: View {
    @Binding var text: String
    var placeholder: String = ""
    var secure = false
    var autoFocus = false
    var maxLength: Int? = nil
    var mono = false
    var clearable = true

    @State private var show = false
    @FocusState private var focus: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    TX(placeholder, .m, 16, C.mute, lines: 1).allowsHitTesting(false)
                }
                Group {
                    if secure && !show {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .font(pfont(.m, 16))
                .foregroundColor(C.text)
                .tint(C.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($focus)
            }
            // RN 의 TextInput 처럼 칸 전체를 눌러도 글자를 쓸 수 있게 (flex:1, height:'100%')
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { focus = true }
            if secure {
                Button { show.toggle() } label: {
                    Icon(show ? "eye-off-outline" : "eye-outline", 20, C.mute).padding(10)
                }
                .buttonStyle(.plain)
                .padding(-10)
            } else if clearable && !text.isEmpty {
                // 한 번에 지우기
                Button { text = ""; focus = true } label: {
                    Icon("close-circle", 20, C.mute).padding(10)
                }
                .buttonStyle(.plain)
                .padding(-10)
                .accessibilityLabel("지우기")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focus ? C.blue : Color.clear, lineWidth: 1.5))
        .onChange(of: text) { _, v in
            if let m = maxLength, v.count > m { text = String(v.prefix(m)) }
        }
        .onAppear {
            if autoFocus { after(0.35) { focus = true } }
        }
    }
}
