import SwiftUI
import CoreImage.CIFilterBuiltins

// src/components/Brand.js — 로고, 원형 QR, 카드, 로고 진행 표시

enum LogoArt {
    static let ARC_LEN: Double = 522 // 반지름 102, 약 293도

    /// 'M199.9 66.1 A102 102 0 1 0 262 160' (320×320 좌표)
    static let arc: Path = {
        var p = Path()
        let cx = 160.0, cy = 160.0, r = 102.0
        let a0 = atan2(66.1 - 160.0, 199.9 - 160.0)
        let sweep = 2 * Double.pi + a0 // 시작점에서 반시계 방향으로 (262,160)까지
        let n = 240
        for i in 0...n {
            let a = a0 - sweep * Double(i) / Double(n)
            let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }()

    static let silver = Gradient(stops: [
        .init(color: Color(hex: "#fcfcfc"), location: 0),
        .init(color: Color(hex: "#c6c6c8"), location: 0.16),
        .init(color: Color(hex: "#ffffff"), location: 0.34),
        .init(color: Color(hex: "#e6e6e7"), location: 0.58),
        .init(color: Color(hex: "#a6a6aa"), location: 0.81),
        .init(color: Color(hex: "#f4f4f5"), location: 1),
    ])
    static let dotGrad = Gradient(stops: [
        .init(color: Color(hex: "#ffffff"), location: 0),
        .init(color: Color(hex: "#f7f7f8"), location: 0.42),
        .init(color: Color(hex: "#b9b9bd"), location: 1),
    ])

    static let thick = StrokeStyle(lineWidth: 40, lineCap: .round)

    /// p: 0→1 그리기, 1→2 지우기 / dot: 0→1 / ring: 0→1 / shine: 0→1
    static func draw(_ ctx: inout GraphicsContext, size: CGFloat, p: Double, dot: Double, ring: Double, shine: Double, track: Bool, mono: Color? = nil) {
        ctx.scaleBy(x: size / 320, y: size / 320)
        // SVG filter#depth: 아래로 1.5 · 흐림 1.2 · 검정 16% 그림자
        if mono == nil && track == false {
            ctx.addFilter(.shadow(color: Color.black.opacity(0.16), radius: 1.2, x: 0, y: 1.5))
        }
        let silverShade: GraphicsContext.Shading = mono.map { GraphicsContext.Shading.color($0) } ??
            .linearGradient(silver, startPoint: CGPoint(x: 76, y: 54), endPoint: CGPoint(x: 255, y: 265))

        // 옅은 바탕 궤도 — 로딩 중에도 로고 자리가 보이게
        if track {
            ctx.stroke(arc, with: .color(Color.white.opacity(0.06)), style: thick)
        }
        // 점이 떨어질 때 퍼지는 잔물결
        if ring > 0 && ring < 1 {
            let rr = 20 + 38 * ring
            let op = ring < 0.1 ? 3.5 * ring : 0.35 * (1 - (ring - 0.1) / 0.9)
            let circle = Path(ellipseIn: CGRect(x: 248 - rr, y: 102 - rr, width: rr * 2, height: rr * 2))
            ctx.stroke(circle, with: .color(Color.white.opacity(op)), lineWidth: 3)
        }
        // 열린 원
        let from = max(0, p - 1), to = min(1, p)
        if to > from + 0.0005 {
            ctx.stroke(arc.trimmedPath(from: from, to: to), with: silverShade, style: thick)
        }
        // 원을 따라 도는 하이라이트
        if shine > 0 && shine < 1 {
            let pos = 60 + (ARC_LEN + 46) * shine
            let a = pos / ARC_LEN, b = min(1, (pos + 46) / ARC_LEN)
            let op: Double = shine < 0.15 ? shine / 0.15 * 0.75 : (shine < 0.85 ? 0.75 : (1 - shine) / 0.15 * 0.75)
            if a < 1 {
                ctx.stroke(arc.trimmedPath(from: a, to: b), with: .color(Color.white.opacity(op)),
                           style: StrokeStyle(lineWidth: 14, lineCap: .round))
            }
        }
        // 점
        if dot > 0.01 {
            let r = 20 * dot
            let cy = 70 + 32 * dot
            let rect = CGRect(x: 248 - r, y: cy - r, width: r * 2, height: r * 2)
            let shade: GraphicsContext.Shading = mono.map { GraphicsContext.Shading.color($0) } ??
                .radialGradient(dotGrad, center: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.minY + rect.height * 0.28),
                                startRadius: 0, endRadius: rect.width * 0.78)
            ctx.fill(Path(ellipseIn: rect), with: shade)
            // SVG: 점 테두리 흰색 20%
            if mono == nil { ctx.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.2)), lineWidth: 1) }
        }
    }
}

// 브랜드 심볼 (assets/brand/ouryn-symbol.svg 를 그대로 옮김)
// SVG 와 같은 320×320 좌표·같은 호(A102)·같은 그라데이션 정지점. 벡터로 그려서 어떤 크기에서도 선명하고,
// 로딩·완료 애니메이션(LogoMark)도 같은 그림을 씀. SVG 래스터와 비교해 가장자리 안티앨리어싱 외 차이 없음
/// 원 안에 로고를 넣을 때의 비율 — 하단 가운데 O 버튼(지름 80 · 로고 62)과 같게
let LOGO_IN_CIRCLE: CGFloat = 62.0 / 80.0

struct Logo: View {
    var size: CGFloat = 28
    var mono: Color? = nil

    var body: some View {
        Canvas { ctx, _ in
            LogoArt.draw(&ctx, size: size, p: 1, dot: 1, ring: 0, shine: 0, track: false, mono: mono)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 로고 진행 표시
// loading: 열린 원이 그려졌다 지워지기를 반복 (점 없음)
// done: 지금 위치에서 원을 끝까지 그린 뒤 → 점이 톡 떨어지고 → 빛이 한 바퀴
// 같은 뷰가 상태만 바뀌므로 크기·위치가 고정된 채 하나의 동작으로 이어짐

enum LogoStatus { case loading, done }

struct LogoMark: View {
    var status: LogoStatus = .done
    var size: CGFloat = 104
    var onDone: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadStart = Date()
    @State private var doneStart: Date? = nil
    @State private var doneFrom: Double = 0
    @State private var finished = false

    private struct Frame { var p: Double; var dot: Double; var ring: Double; var shine: Double }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished || reduceMotion)) { tl in
            let f = frame(tl.date)
            Canvas { ctx, _ in
                LogoArt.draw(&ctx, size: size, p: f.p, dot: f.dot, ring: f.ring, shine: f.shine, track: true)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if status == .done { begin(from: 0) } else { loadStart = Date() }
        }
        .onChange(of: status) { _, s in
            if s == .done {
                begin(from: loadingP(Date()))
            } else {
                finished = false
                doneStart = nil
                loadStart = Date()
            }
        }
    }

    private func loadingP(_ d: Date) -> Double {
        let t = d.timeIntervalSince(loadStart).truncatingRemainder(dividingBy: 1.5) / 1.5
        return 2 * Curve.inOutCubic(t)
    }

    private var eraseDur: Double { max(0.12, (2 - doneFrom) * 0.5) }
    private var drawDur: Double {
        doneFrom <= 1 ? max(0.18, (1 - doneFrom) * 0.65) : eraseDur + 0.52
    }

    private func frame(_ date: Date) -> Frame {
        // 동작 줄이기: 그리기·지우기 없이 완성된 로고(로딩 중엔 점 없이)만
        if reduceMotion { return Frame(p: 1, dot: doneStart == nil ? 0 : 1, ring: 0, shine: 0) }
        guard let ds = doneStart else {
            return Frame(p: loadingP(date), dot: 0, ring: 0, shine: 0)
        }
        let t = date.timeIntervalSince(ds)
        let p: Double
        if doneFrom <= 1 {
            p = doneFrom + (1 - doneFrom) * Curve.outCubic(Curve.clamp(t / drawDur))
        } else if t < eraseDur {
            p = doneFrom + (2 - doneFrom) * Curve.inQuad(Curve.clamp(t / eraseDur))
        } else {
            p = Curve.outCubic(Curve.clamp((t - eraseDur) / 0.52))
        }
        let t2 = t - drawDur
        let dot = t2 > 0 ? Curve.spring(t2) : 0
        let ring = t2 > 0 ? Curve.outQuad(Curve.clamp(t2 / 0.6)) : 0
        let shine = t2 > 0.12 ? Curve.inOutCubic(Curve.clamp((t2 - 0.12) / 0.7)) : 0
        return Frame(p: p, dot: dot, ring: ring, shine: shine)
    }

    private func begin(from v: Double) {
        doneFrom = v
        doneStart = Date()
        finished = false
        if reduceMotion {
            haptic(.success)
            after(0.2) { onDone?() }
            return
        }
        let d = v <= 1 ? max(0.18, (1 - v) * 0.65) : max(0.12, (2 - v) * 0.5) + 0.52
        after(v <= 1 ? d : 0.9) { haptic(.success) }
        after(d + 0.85) { onDone?() }
        after(d + 1.4) { if doneStart != nil { finished = true } }
    }
}

struct DoneMark: View {
    var size: CGFloat = 104
    var onDone: (() -> Void)? = nil
    var body: some View { LogoMark(status: .done, size: size, onDone: onDone) }
}

// MARK: - 원형 QR
// 원 전체가 같은 크기의 둥근 점으로 채워진 '귀여운' 원형 코드. 속은 표준 QR(오류 복원 Q).
// - 주소만 담아서(solana:<주소> 등) 칸 수가 37~41 로 작음 → 점이 크고 적어짐
//   금액을 넣은 요청은 표준 Solana Pay 라 내용이 길어(53칸) 받기 화면에서 네모 표준 QR 로 따로 그림
// - 원의 나머지도 같은 간격·크기·밀도의 점으로 채워 네모 경계를 숨김 (QR 둘레는 1칸만 비움)
// - 가운데 검은 원 + 로고: 오류 복원 Q 로 가려진 칸을 복구 (원 반지름 = 지름의 12%)
// - 찾기 패턴(세 귀퉁이)은 동그라미 과녁 — 시뮬레이션(ZXing 30/40)보다 실기기 아이폰 카메라가 잘 읽음 (2026-09-23 확인)
// - 네 번째 장식 눈은 넣지 않음: 스캐너가 방향을 헷갈려 인식률이 크게 떨어짐 (ZXing 24/40)

enum QRMatrix {
    private static let ctx = CIContext()
    private static var cache: [String: [[Bool]]] = [:]

    /// 글자 → 모듈 표 (true = 검은 칸). 조용한 영역은 뺀 순수 QR
    static func make(_ text: String) -> [[Bool]] {
        if let c = cache[text] { return c }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "Q"
        guard let img = f.outputImage, let cg = ctx.createCGImage(img, from: img.extent) else { return [] }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 255, count: w * h)
        px.withUnsafeMutableBytes { buf in
            let bm = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            bm?.interpolationQuality = .none
            bm?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[y * w + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return [] }
        let m = (minY...maxY).map { y in (minX...maxX).map { x in px[y * w + x] < 128 } }
        cache[text] = m
        return m
    }
}

struct RoundQR: View {
    let value: String
    var size: CGFloat = 260

    var body: some View {
        let mat = QRMatrix.make(value)
        let n = max(mat.count, 21)
        let D = Double(size)
        let side = D * 0.62                 // QR 한 변
        let m = side / Double(n)            // 한 칸
        let x0 = (D - side) / 2, y0 = (D - side) / 2
        let R = D * 0.12                    // 가운데 검은 원 반지름
        let dot = m * 0.425                 // 점 반지름 (QR·장식 모두 같음)
        ZStack {
            Canvas { ctx, _ in
                func circle(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                }
                // 바탕 원
                ctx.fill(circle(D / 2, D / 2, D / 2), with: .color(C.text))

                // 둘레 장식 점 (QR 과 같은 간격, QR 둘레 1칸 밖)
                var seed: UInt64 = 7
                for u in value.utf8 { seed = (seed &* 31 &+ UInt64(u)) & 0xFFFF_FFFF }
                func rnd() -> Double {
                    seed = (seed &* 1_664_525 &+ 1_013_904_223) & 0xFFFF_FFFF
                    return Double(seed) / 4_294_967_296
                }
                let span = Int(ceil(D / m))
                let startI = -Int(ceil(x0 / m))
                for j in startI..<(startI + span + 1) {
                    for i in startI..<(startI + span + 1) {
                        let cx = x0 + (Double(i) + 0.5) * m, cy = y0 + (Double(j) + 0.5) * m
                        let inQR = i >= -1 && i < n + 1 && j >= -1 && j < n + 1
                        if inQR || hypot(cx - D / 2, cy - D / 2) > D / 2 - m * 1.3 { continue }
                        if rnd() > 0.48 { ctx.fill(circle(cx, cy, dot), with: .color(C.bg)) }
                    }
                }

                // QR 모듈 = 점 (찾기 패턴 자리와 가운데 로고 자리는 건너뜀)
                func inFinder(_ r: Int, _ c: Int) -> Bool {
                    (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7)
                }
                for (r, row) in mat.enumerated() {
                    for (c, on) in row.enumerated() where on && !inFinder(r, c) {
                        let cx = x0 + (Double(c) + 0.5) * m, cy = y0 + (Double(r) + 0.5) * m
                        if hypot(cx - D / 2, cy - D / 2) < R + m * 0.6 { continue }
                        ctx.fill(circle(cx, cy, dot), with: .color(C.bg))
                    }
                }
                // 찾기 패턴: 동그라미 과녁 (바깥 7칸 고리 · 가운데 3칸 점)
                for (fr, fc) in [(0, 0), (0, n - 7), (n - 7, 0)] {
                    let fcx = x0 + (Double(fc) + 3.5) * m, fcy = y0 + (Double(fr) + 3.5) * m
                    var ring = circle(fcx, fcy, 3.5 * m)
                    ring.addPath(circle(fcx, fcy, 2.5 * m))
                    ctx.fill(ring, with: .color(C.bg), style: FillStyle(eoFill: true))
                    ctx.fill(circle(fcx, fcy, 1.5 * m), with: .color(C.bg))
                }
                // 가운데 검은 원
                ctx.fill(circle(D / 2, D / 2, R), with: .color(C.bg))
            }
            Logo(size: CGFloat(R * 1.45)) // 로고가 검은 원 지름의 약 55%
        }
        .frame(width: size, height: size)
        .accessibilityLabel("내 지갑 QR 코드")
    }
}

// MARK: - 카드 앞면

struct CardFace: View {
    var width: CGFloat = 320
    var name = "내 이름"
    var dim = false

    var body: some View {
        let h = width * 0.63
        let mini = width < 140
        ZStack(alignment: .topLeading) {
            Canvas { ctx, sz in
                let w = sz.width, hh = sz.height
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: hh)),
                         with: .linearGradient(Gradient(colors: [Color(hex: "#1C1C21"), Color(hex: "#0A0A0C")]),
                                               startPoint: .zero, endPoint: CGPoint(x: w, y: hh)))
                let r = hh * 0.52
                let c = CGPoint(x: w * 0.82, y: hh * 0.62)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.stroke(Path(ellipseIn: rect),
                           with: .linearGradient(Gradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.02)]),
                                                 startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)),
                           lineWidth: hh * 0.16)
                let chip = CGRect(x: w * 0.08, y: hh * 0.42, width: w * 0.13, height: hh * 0.16)
                ctx.fill(Path(roundedRect: chip, cornerRadius: 5), with: .color(Color(hex: "#B9B9BD").opacity(0.6)))
            }
            Logo(size: mini ? 12 : 30)
                .padding(.top, mini ? 6 : 18)
                .padding(.leading, mini ? 7 : 20)
            if !mini {
                VStack {
                    Spacer()
                    HStack {
                        TX(name, .sb, 13, Color(hex: "#C9C9CD"), tracking: 1)
                        Spacer()
                        TX("체크카드", .m, 12, Color(hex: "#8A8A92"))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(width: width, height: h)
        .background(Color(hex: "#111114"))
        .clipShape(RoundedRectangle(cornerRadius: mini ? 6 : 18))
        .overlay(RoundedRectangle(cornerRadius: mini ? 6 : 18).strokeBorder(Color(hex: "#2A2A30"), lineWidth: 1))
        .opacity(dim ? 0.55 : 1)
    }
}
