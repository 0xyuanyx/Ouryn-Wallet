import Foundation

// src/format.js 그대로

/// 1달러 = 몇 원. 동기화 때 테더 원화 시세로 바뀜 (처음엔 대략값)
var RATE: Double = 1390

/// JS Math.round
func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

private let koInt: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "ko_KR")
    f.maximumFractionDigits = 0
    return f
}()

private let ko4: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "ko_KR")
    f.maximumFractionDigits = 4
    return f
}()

private let en2: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US")
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
}()

private let enInt: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US")
    f.maximumFractionDigits = 0
    return f
}()

/// 1234 → "1,234"
func grouped(_ n: Double) -> String { koInt.string(from: NSNumber(value: n)) ?? "\(Int(n))" }
func grouped4(_ n: Double) -> String { ko4.string(from: NSNumber(value: n)) ?? "\(n)" }
func groupedEn(_ n: Double) -> String { enInt.string(from: NSNumber(value: n)) ?? "\(Int(n))" }

func krw(_ usd: Double) -> Double { jsRound(usd * RATE) }
func won(_ n: Double) -> String { grouped(jsRound(n)) + "원" }
func wonOf(_ usd: Double) -> String { won(usd * RATE) }
func dollar(_ n: Double) -> String { (en2.string(from: NSNumber(value: n)) ?? String(format: "%.2f", n)) + "달러" }

func short(_ a: String?) -> String {
    guard let a = a, !a.isEmpty else { return "" }
    guard a.count > 14 else { return a }
    return String(a.prefix(6)) + "···" + String(a.suffix(6))
}

private func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
private let cal = Calendar.current

func dayLabel(_ ts: Date) -> String {
    let now = Date()
    if cal.isDate(ts, inSameDayAs: now) { return "오늘" }
    if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(ts, inSameDayAs: y) { return "어제" }
    let c = cal.dateComponents([.month, .day, .weekday], from: ts)
    let w = ["일", "월", "화", "수", "목", "금", "토"][(c.weekday ?? 1) - 1]
    return "\(c.month ?? 1)월 \(c.day ?? 1)일 \(w)요일"
}

func timeLabel(_ ts: Date) -> String {
    let c = cal.dateComponents([.hour, .minute], from: ts)
    let h = c.hour ?? 0
    let h12 = h % 12 == 0 ? 12 : h % 12
    return "\(h < 12 ? "오전" : "오후") \(h12):\(pad(c.minute ?? 0))"
}

func fullDate(_ ts: Date) -> String {
    let c = cal.dateComponents([.year, .month, .day], from: ts)
    return "\(c.year ?? 0)년 \(c.month ?? 1)월 \(c.day ?? 1)일 \(timeLabel(ts))"
}

func relTime(_ ts: Date) -> String {
    let s = Date().timeIntervalSince(ts)
    if s < 60 { return "방금" }
    if s < 3600 { return "\(Int(s / 60))분 전" }
    if s < 86400 { return "\(Int(s / 3600))시간 전" }
    return "\(Int(s / 86400))일 전"
}

func randomAddr() -> String {
    let cs = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    return String((0..<44).map { _ in cs[Int.random(in: 0..<cs.count)] })
}

func randomHash() -> String { randomAddr() + String(randomAddr().prefix(20)) }

/// 조사 붙이기: josa("이더리움", "을/를") → "이더리움을"
func josa(_ word: String, _ pair: String) -> String {
    let parts = pair.split(separator: "/").map(String.init)
    let a = parts[0], b = parts.count > 1 ? parts[1] : parts[0]
    let hangul = word.unicodeScalars.filter { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }
    guard let ch = hangul.last else { return word + b }
    let jong = (Int(ch.value) - 0xAC00) % 28
    if pair == "으로/로" { return word + ((jong == 0 || jong == 8) ? b : a) } // ㄹ 받침은 '로'
    return word + (jong != 0 ? a : b)
}

/// 받침이 있는지 (이라도/라도 등)
func hasBatchim(_ word: String) -> Bool {
    guard let ch = word.unicodeScalars.last, ch.value >= 0xAC00, ch.value <= 0xD7A3 else { return false }
    return (Int(ch.value) - 0xAC00) % 28 != 0
}

/// 퍼센트 표시 (+1.8%)
func pct(_ c: Double) -> String { "\(c > 0 ? "+" : "")\(String(format: "%.1f", c))%" }

/// 수량 표시 (개)
func qtyText(_ n: Double) -> String { (n >= 100 ? grouped(jsRound(n)) : grouped4(n)) + "개" }

/// JS Number → 문자열 (0.01 → "0.01", 500 → "500", 21.58273381294964 → 같은 최단 표기)
func jsNum(_ n: Double) -> String {
    if n == n.rounded() && abs(n) < 1e15 { return String(Int(n)) }
    return "\(n)"
}

/// 수량 숫자만 (개 없이)
func qtyPlain(_ n: Double) -> String { n >= 100 ? grouped(jsRound(n)) : grouped4(n) }
