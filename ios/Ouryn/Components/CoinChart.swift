import SwiftUI

// src/components/CoinChart.js

struct Period: Equatable {
    let key: String
    let label: String
    let n: Int
    let step: TimeInterval
    let word: String
}

// 기간별 점 개수와 한 칸의 시간
let PERIODS: [Period] = [
    Period(key: "1d", label: "1일", n: 48, step: 30 * 60, word: "오늘"),
    Period(key: "1w", label: "1주", n: 56, step: 3 * 3600, word: "1주"),
    Period(key: "1m", label: "1달", n: 60, step: 12 * 3600, word: "1달"),
    Period(key: "1y", label: "1년", n: 52, step: 7 * 86400, word: "1년"),
]

struct ChartPoint { let t: Date; let v: Double }

private func timeText(_ ts: Date, _ key: String) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: ts)
    let h = c.hour ?? 0
    let m = c.minute ?? 0
    let hm = "\(h < 12 ? "오전" : "오후") \(h % 12 == 0 ? 12 : h % 12):\(m < 10 ? "0" : "")\(m)"
    if key == "1d" { return hm }
    if key == "1y" { return "\(c.year ?? 0)년 \(c.month ?? 1)월 \(c.day ?? 1)일" }
    return "\(c.month ?? 1)월 \(c.day ?? 1)일 \(hm)"
}

struct CoinChart: View {
    let id: String
    let price: Double
    let change: Double
    var height: CGFloat = 180

    @State private var pk = "1d"
    @State private var hover: Int? = nil
    @State private var cache: [String: [ChartPoint]] = [:]
    @State private var failed: Set<String> = []

    private var period: Period { PERIODS.first { $0.key == pk } ?? PERIODS[0] }
    private let days = ["1d": "1", "1w": "7", "1m": "30", "1y": "365"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pts = cache[pk], pts.count >= 2 {
                chartBody(pts)
            } else {
                VStack(spacing: 8) {
                    if failed.contains(pk) {
                        Icon("cloud-offline-outline", 22, C.mute)
                        TX("시세를 불러오지 못했어요", .r, 13, C.mute)
                        Tap(action: { failed.remove(pk); Task { await load(pk) } }) {
                            TX("다시 시도", .m, 13, C.sub).padding(.vertical, 6)
                        }
                    } else {
                        ProgressView().tint(C.mute)
                        TX("실제 시세를 불러오는 중", .r, 13, C.mute)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: height + 50)
            }

            HStack {
                ForEach(Array(PERIODS.enumerated()), id: \.offset) { i, p in
                    if i > 0 { Spacer() }
                    Pill(label: p.label, active: p.key == pk) { pk = p.key; hover = nil }
                }
            }
            .padding(.top, 14)
            TX("그래프를 누른 채 움직이면 그때 가격이 보여요 · 시세 CoinGecko", .r, 11, C.mute, align: .center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
        .task(id: pk) { await load(pk) }
    }

    private func load(_ key: String) async {
        if cache[key] != nil { return }
        guard let d = days[key], let raw = await ChainAPI.chart(id, days: d) else {
            await MainActor.run { _ = failed.insert(key) }
            return
        }
        // 기간마다 점 개수를 맞춤 (너무 촘촘하면 손가락으로 읽기 어려움)
        let n = (PERIODS.first { $0.key == key } ?? PERIODS[0]).n
        let step = max(1, raw.count / n)
        var pts: [ChartPoint] = stride(from: 0, to: raw.count, by: step).map { ChartPoint(t: raw[$0].0, v: raw[$0].1) }
        if let last = raw.last, pts.last?.t != last.0 { pts.append(ChartPoint(t: last.0, v: last.1)) }
        await MainActor.run { cache[key] = pts }
    }

    @ViewBuilder
    private func chartBody(_ pts: [ChartPoint]) -> some View {
        let data = pts.map { $0.v }
        let mn = data.min() ?? 0, mx = data.max() ?? 1
        let shown = hover.map { data[$0] } ?? data[data.count - 1]
        let diff = shown - data[0]
        let pctv = data[0] == 0 ? 0 : diff / data[0] * 100
        let when = hover.map { timeText(pts[$0].t, period.key) } ?? "\(period.word) 동안"

        VStack(alignment: .leading, spacing: 0) {
            TX(won(shown), .b, 22).monospacedDigit()
            (tt("\(diff >= 0 ? "+" : "")\(won(diff)) (\(pctv >= 0 ? "+" : "")\(String(format: "%.2f", pctv))%) ", .m, 13, diff >= 0 ? C.up : C.down)
                + tt("· \(when)", .r, 13, C.mute))
                .monospacedDigit()
                .padding(.top, 3)
        }
        .padding(.bottom, 12)

        GeometryReader { geo in
            plot(data: data, mn: mn, mx: mx, w: geo.size.width)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let i = idxAt(g.location.x, geo.size.width, data.count)
                            if hover == nil { haptic(.select) }
                            if i != hover { hover = i }
                        }
                        .onEnded { _ in hover = nil }
                )
        }
        .frame(height: height)
    }

    private func idxAt(_ px: CGFloat, _ w: CGFloat, _ n: Int) -> Int {
        max(0, min(n - 1, Int(((px / max(w, 1)) * CGFloat(n - 1)).rounded())))
    }

    @ViewBuilder
    private func plot(data: [Double], mn: Double, mx: Double, w: CGFloat) -> some View {
        let padTop: CGFloat = 22, padBottom: CGFloat = 22 // 최고·최저 표시 자리
        let h = height
        let range = (mx - mn) == 0 ? 1 : (mx - mn)
        let yOf: (Double) -> CGFloat = { v in padTop + CGFloat(1 - (v - mn) / range) * (h - padTop - padBottom) }
        let xOf: (Int) -> CGFloat = { i in CGFloat(i) / CGFloat(data.count - 1) * w }
        let up = data[data.count - 1] >= data[0]
        let color = up ? C.up : C.down
        let iMax = data.firstIndex(of: mx) ?? 0
        let iMin = data.firstIndex(of: mn) ?? 0
        let LW: CGFloat = 170 // 최고·최저 글자 칸 너비
        let labelX: (Int) -> CGFloat = { i in max(0, min(w - LW, xOf(i) - LW / 2)) }
        let alignOf: (Int) -> Alignment = { i in xOf(i) < LW / 2 ? .leading : (xOf(i) > w - LW / 2 ? .trailing : .center) }

        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                var line = Path()
                for (i, v) in data.enumerated() {
                    let p = CGPoint(x: xOf(i), y: yOf(v))
                    if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                var area = line
                area.addLine(to: CGPoint(x: w, y: h))
                area.addLine(to: CGPoint(x: 0, y: h))
                area.closeSubpath()
                // 시작 가격 기준선
                var base = Path()
                base.move(to: CGPoint(x: 0, y: yOf(data[0])))
                base.addLine(to: CGPoint(x: w, y: yOf(data[0])))
                ctx.stroke(base, with: .color(C.faint), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.2), color.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                func dot(_ g: inout GraphicsContext, _ i: Int, _ r: CGFloat) {
                    let c = CGPoint(x: xOf(i), y: yOf(data[i]))
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    g.fill(Path(ellipseIn: rect), with: .color(color))
                    g.stroke(Path(ellipseIn: rect), with: .color(C.surface), lineWidth: 2)
                }
                if let hv = hover {
                    var v = Path()
                    v.move(to: CGPoint(x: xOf(hv), y: 0))
                    v.addLine(to: CGPoint(x: xOf(hv), y: h))
                    ctx.stroke(v, with: .color(C.sub), lineWidth: 1)
                    dot(&ctx, hv, 6)
                } else {
                    dot(&ctx, data.count - 1, 5)
                }
            }
            .frame(width: w, height: h)
            if hover == nil {
                TX("최고 \(won(mx))", .r, 11, C.mute, lines: 1)
                    .frame(width: LW, alignment: alignOf(iMax))
                    .offset(x: labelX(iMax), y: 2)
                TX("최저 \(won(mn))", .r, 11, C.mute, lines: 1)
                    .frame(width: LW, alignment: alignOf(iMin))
                    .offset(x: labelX(iMin), y: h - 16)
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }
}
