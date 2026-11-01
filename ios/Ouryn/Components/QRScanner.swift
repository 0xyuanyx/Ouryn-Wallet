import SwiftUI
import AVFoundation
import CoreImage

// 실제 카메라로 QR 읽기 (AVFoundation)
// 시뮬레이터처럼 카메라가 없으면 available == false → 화면에서 체험용 인식으로 대신

final class QRScannerView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    static var available: Bool { AVCaptureDevice.default(for: .video) != nil }

    /// 읽은 글자 + 화면(윈도우) 좌표계에서 QR이 있는 사각형
    var onCode: ((String, CGRect) -> Void)?
    var paused = false

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var device: AVCaptureDevice?
    private let queue = DispatchQueue(label: "ouryn.camera")

    override func layoutSubviews() {
        super.layoutSubviews()
        preview?.frame = bounds
    }

    @discardableResult
    func start() -> Bool {
        guard let dev = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        let out = AVCaptureMetadataOutput()
        guard session.canAddOutput(out) else { return false }
        session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
        out.metadataObjectTypes = [.qr]
        device = dev

        let p = AVCaptureVideoPreviewLayer(session: session)
        p.videoGravity = .resizeAspectFill
        layer.addSublayer(p)
        preview = p
        p.frame = bounds

        let s = session
        queue.async { s.startRunning() }
        return true
    }

    func stop() {
        let s = session
        queue.async { if s.isRunning { s.stopRunning() } }
    }

    func setTorch(_ on: Bool) {
        guard let d = device, d.hasTorch else { return }
        let mode: AVCaptureDevice.TorchMode = on ? .on : .off
        guard d.torchMode != mode, d.isTorchModeSupported(mode),
              (try? d.lockForConfiguration()) != nil else { return }
        d.torchMode = mode
        d.unlockForConfiguration()
    }

    /// 마지막 프레임에서 화면만 멈춤 (세션은 계속 → 다시 켜면 바로 이어짐)
    func freeze(_ on: Bool) {
        if preview?.connection?.isEnabled == on { preview?.connection?.isEnabled = !on }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !paused,
              let o = objects.first as? AVMetadataMachineReadableCodeObject,
              let s = o.stringValue else { return }
        // 카메라 좌표 → 이 뷰 좌표 → 윈도우 좌표
        // 네 꼭짓점 기준 → 기울어진 QR도 모서리까지 원 안에
        let t = preview?.transformedMetadataObject(for: o) as? AVMetadataMachineReadableCodeObject
        let local = t.map { qrCircleBox(corners: $0.corners, fallback: $0.bounds) } ?? .zero
        onCode?(s, local.isEmpty ? .zero : convert(local, to: nil))
    }
}

struct QRCamera: UIViewRepresentable {
    var torch: Bool
    var paused: Bool
    var frozen: Bool = false
    let onCode: (String, CGRect) -> Void

    func makeUIView(context: Context) -> QRScannerView {
        let v = QRScannerView()
        v.backgroundColor = .black
        v.onCode = onCode
        v.start()
        return v
    }

    func updateUIView(_ v: QRScannerView, context: Context) {
        v.onCode = onCode
        v.paused = paused
        v.setTorch(torch)
        v.freeze(frozen)
    }

    static func dismantleUIView(_ v: QRScannerView, coordinator: ()) {
        v.setTorch(false)
        v.stop()
    }
}

/// 사진 속 QR 읽기 (스크린샷으로 한 대에서도 시험해볼 수 있게)
func readQR(fromImageData data: Data) -> String? {
    guard let img = CIImage(data: data),
          let det = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    else { return nil }
    return det.features(in: img).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
}

func readQRCodes(fromImageData data: Data) -> [String] {
    guard let image = CIImage(data:data), let detector = CIDetector(ofType:CIDetectorTypeQRCode,context:nil,options:[CIDetectorAccuracy:CIDetectorAccuracyHigh]) else { return [] }
    return Array(Set(detector.features(in:image).compactMap { ($0 as? CIQRCodeFeature)?.messageString })).sorted()
}

/// 사진 속 QR — 내용 + 위치 (사진 기준 0~1, 왼쪽 위 원점)
struct StillQR: Sendable {
    let text: String
    let rect: CGRect
}

func readQRStill(fromImageData data: Data) -> StillQR? {
    // 사진 방향(EXIF)을 적용해야 UIImage 로 그린 모습과 좌표가 맞음
    guard let img = CIImage(data: data, options: [.applyOrientationProperty: true]),
          let det = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    else { return nil }
    let e = img.extent
    guard e.width > 0, e.height > 0,
          let f = det.features(in: img).compactMap({ $0 as? CIQRCodeFeature }).first(where: { $0.messageString != nil }),
          let text = f.messageString
    else { return nil }
    let b = qrCircleBox(corners: [f.topLeft, f.topRight, f.bottomRight, f.bottomLeft], fallback: f.bounds)
    // Core Image 는 왼쪽 아래 원점 → 왼쪽 위 원점으로
    let r = CGRect(x: (b.minX - e.minX) / e.width,
                   y: 1 - (b.maxY - e.minY) / e.height,
                   width: b.width / e.width,
                   height: b.height / e.height)
    return StillQR(text: text, rect: r)
}

/// QR 네 꼭짓점 → QR을 모서리까지 감싸는 원의 바깥 정사각형 (가운데 = 꼭짓점 평균)
/// 꼭짓점을 모르면 사각형의 대각선으로
func qrCircleBox(corners: [CGPoint], fallback: CGRect) -> CGRect {
    var cx: CGFloat = 0
    var cy: CGFloat = 0
    var r: CGFloat = 0
    if corners.count >= 4 {
        for p in corners { cx += p.x; cy += p.y }
        cx /= CGFloat(corners.count)
        cy /= CGFloat(corners.count)
        for p in corners { r = max(r, hypot(p.x - cx, p.y - cy)) }
    } else {
        guard !fallback.isEmpty else { return .zero }
        cx = fallback.midX
        cy = fallback.midY
        r = hypot(fallback.width, fallback.height) / 2
    }
    guard r > 0 else { return .zero }
    return CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
}
