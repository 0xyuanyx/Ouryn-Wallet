import SwiftUI

// src/components/AmountEntry.js
// 원 또는 달러로 금액 입력. onChange(usd, over) 로 달러 값을 넘김

struct AmountEntry: View {
    var max: Double? = nil
    var maxLabel = "보낼 수 있는 돈"
    var defaultUnit = "krw"
    var quick = true
    var receiving = false
    let onChange: (Double, Bool) -> Void

    @State private var unit: String? = nil
    @State private var raw = ""

    private var u: String { unit ?? defaultUnit }

    private var usd: Double {
        if raw.isEmpty { return 0 }
        if u == "krw" { return (Double(raw) ?? 0) / RATE }
        return Double(raw) ?? 0
    }
    private var over: Bool {
        guard let m = max else { return false }
        return usd > m + 1e-9
    }

    private var display: String {
        if raw.isEmpty {
            if receiving { return u == "krw" ? "얼마를 받을까요?" : "몇 달러를 받을까요?" }
            return u == "krw" ? "얼마를 보낼까요?" : "몇 달러를 보낼까요?"
        }
        if u == "krw" { return grouped(Double(raw) ?? 0) + "원" }
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let i = groupedEn(Double(parts[0].isEmpty ? "0" : parts[0]) ?? 0)
        let d = parts.count > 1 ? "." + parts[1] : ""
        return i + d + "달러"
    }

    private func onKey(_ k: String) {
        if k == "del" { if !raw.isEmpty { raw.removeLast() }; return }
        if u == "krw" {
            if k == "." { return }
            if raw.count >= 10 { return }
            raw = raw == "0" ? k : raw + k
            return
        }
        if k == "." {
            if raw.contains(".") { return }
            raw = (raw.isEmpty ? "0" : raw) + "."
            return
        }
        if raw.contains("."), let dec = raw.split(separator: ".", omittingEmptySubsequences: false).last, dec.count >= 2 { return }
        if raw.replacingOccurrences(of: ".", with: "").count >= 9 { return }
        raw = raw == "0" ? k : raw + k
    }

    private func addKrw(_ n: Int) {
        haptic(.select)
        let cur: Int = u == "krw" ? Int(raw.isEmpty ? "0" : raw) ?? 0 : Int(jsRound((Double(raw.isEmpty ? "0" : raw) ?? 0) * RATE))
        unit = "krw"
        raw = String(cur + n)
    }

    private func setAll() {
        haptic(.select)
        guard let m = max else { return }
        if u == "krw" {
            raw = String(Int((m * RATE).rounded(.down)))
        } else {
            var s = String(format: "%.2f", (m * 100).rounded(.down) / 100)
            if s.hasSuffix(".00") { s = String(s.dropLast(3)) }
            raw = s
        }
    }

    private func toggle() {
        haptic(.select)
        if raw.isEmpty { unit = u == "krw" ? "usd" : "krw"; return }
        let v = usd
        if u == "krw" {
            unit = "usd"
            raw = jsNum((v * 100).rounded() / 100)
        } else {
            unit = "krw"
            raw = String(Int(jsRound(v * RATE)))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TX(display, .b, raw.isEmpty ? 30 : 38, raw.isEmpty ? C.mute : (over ? C.red : C.text), lines: 1, tracking: -1)
                    .minimumScaleFactor(0.4)
                Button(action: toggle) {
                    HStack(spacing: 4) {
                        TX(u == "krw" ? (raw.isEmpty ? "달러로 입력" : dollar(usd)) : (raw.isEmpty ? "원화로 입력" : won(usd * RATE)), .r, 14, C.sub)
                        Icon("swap-vertical", 14, C.sub)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(C.surface))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                if let m = max {
                    TX((over ? "잔액이 부족해요 · " : "") + "\(maxLabel) \(won(m * RATE))", .r, 14, over ? C.red : C.mute)
                        .padding(.top, 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            if quick {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("+1만") { addKrw(10000) }
                        chip("+5만") { addKrw(50000) }
                        chip("+10만") { addKrw(100000) }
                        if max != nil { chip("전부") { setAll() } }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Keypad(extra: u == "usd" ? "." : nil, onKey: onKey)
                .padding(.horizontal, 12)
        }
        .onChange(of: raw) { _, _ in onChange(usd, over) }
        .onChange(of: unit) { _, _ in onChange(usd, over) }
        .onAppear { onChange(usd, over) }
    }

    private func chip(_ label: String, _ action: @escaping () -> Void) -> some View {
        Tap(action: action) {
            TX(label, .m, 14, C.sub)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(C.surface))
        }
    }
}
