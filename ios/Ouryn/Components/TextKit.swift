import SwiftUI

// base.js 의 <T> — Pretendard, 자간 -0.2

/// 이어 붙일 수 있는 글자 (중첩 <T> 대응)
func tt(_ s: String, _ w: W = .r, _ size: CGFloat = 15, _ color: Color = C.text) -> Text {
    Text(s).font(pfont(w, size)).kerning(-0.2).foregroundColor(color)
}

/// RN lineHeight → SwiftUI lineSpacing
func lineGap(_ size: CGFloat, _ lh: CGFloat?) -> CGFloat {
    guard let lh = lh else { return 0 }
    return max(0, lh - size * 1.193)
}

struct TX: View {
    let s: String
    var w: W
    var size: CGFloat
    var color: Color
    var lh: CGFloat?
    var align: TextAlignment
    var lines: Int?
    var tracking: CGFloat

    init(_ s: String, _ w: W = .r, _ size: CGFloat = 15, _ color: Color = C.text,
         lh: CGFloat? = nil, align: TextAlignment = .leading, lines: Int? = nil, tracking: CGFloat = -0.2) {
        self.s = s
        self.w = w
        self.size = size
        self.color = color
        self.lh = lh
        self.align = align
        self.lines = lines
        self.tracking = tracking
    }

    var body: some View {
        Text(s)
            .font(pfont(w, size))
            .kerning(tracking)
            .foregroundColor(color)
            .lineSpacing(lineGap(size, lh))
            .multilineTextAlignment(align)
            .lineLimit(lines)
    }
}

/// 여러 스타일이 섞인 글자
struct TXRich: View {
    let text: Text
    var size: CGFloat = 15
    var lh: CGFloat? = nil
    var align: TextAlignment = .leading

    var body: some View {
        text
            .lineSpacing(lineGap(size, lh))
            .multilineTextAlignment(align)
    }
}
