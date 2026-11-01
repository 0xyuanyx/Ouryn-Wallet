import Foundation
import LocalAuthentication

// src/bio.js — 얼굴 인식 / 지문 사용 가능 여부와 이름

struct BioInfo {
    var ok: Bool
    var label: String
    var icon: String
}

enum Bio {
    static func info() -> BioInfo {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            return BioInfo(ok: false, label: "생체 인증", icon: "finger-print")
        }
        let face = ctx.biometryType == .faceID
        return BioInfo(ok: true, label: face ? "얼굴 인식" : "지문", icon: face ? "scan-circle" : "finger-print")
    }

    /// 성공하면 true (기기 암호로 대체하지 않음)
    static func auth(_ reason: String = "본인 확인", _ done: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "취소"
        ctx.localizedFallbackTitle = ""
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    /// 앱 열기·비밀번호 다시 정하기처럼 '마지막으로 받아들인 얼굴 등록 그대로'일 때만 믿는 확인
    /// 인증에 쓴 바로 그 context 의 등록 상태를 저장된 기준(Biometry)과 비교함
    /// → 화면을 띄워 둔 채 설정에서 얼굴을 새로 등록하고 돌아와도 통과하지 못함
    static func authTrusted(_ reason: String, _ done: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "취소"
        ctx.localizedFallbackTitle = ""
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
            let same = ok && Biometry.isAccepted(ctx.evaluatedPolicyDomainState)
            DispatchQueue.main.async { done(same) }
        }
    }
}
