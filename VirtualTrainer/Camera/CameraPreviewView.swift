import SwiftUI
import AVFoundation

// ────────────────────────────────────────────────────────────────────
// MARK: - CameraPreviewView
// ────────────────────────────────────────────────────────────────────

/// Bridges AVCaptureVideoPreviewLayer into SwiftUI.
///
/// Stretches to fill the parent frame. The preview layer auto-rotates
/// with the device because it's backed by the capture session.
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}
