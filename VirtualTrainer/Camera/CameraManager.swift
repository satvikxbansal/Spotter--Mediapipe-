import AVFoundation
import Combine
import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - CameraManager
// ────────────────────────────────────────────────────────────────────

/// Owns the `AVCaptureSession` lifecycle **and** delivers sample
/// buffers to a frame handler for MediaPipe pose processing.
///
/// Views observe `isRunning` reactively; all capture-session work
/// happens on a dedicated serial queue so the main thread stays free.
final class CameraManager: NSObject, ObservableObject {

    let session = AVCaptureSession()

    @Published var isRunning = false
    @Published var permissionGranted = false

    /// Set this closure before calling `start()`. It receives every
    /// video frame's sample buffer on a dedicated processing queue —
    /// never the main thread. MediaPipe accepts CMSampleBuffer
    /// directly via MPImage.
    var onFrame: ((CMSampleBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.virtualtrainer.camera.session")
    private let videoOutputQueue = DispatchQueue(
        label: "com.virtualtrainer.camera.videoOutput",
        qos: .userInitiated
    )
    private let videoOutput = AVCaptureVideoDataOutput()

    // MARK: - Public API

    func start() {
        checkPermission { [weak self] granted in
            guard let self, granted else { return }
            self.sessionQueue.async { self.configureSession() }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - Permission

    private func checkPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.permissionGranted = true }
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { self?.permissionGranted = granted }
                completion(granted)
            }
        default:
            DispatchQueue.main.async { self.permissionGranted = false }
            completion(false)
        }
    }

    // MARK: - Session Configuration

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Input
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // Video data output — delivers sample buffers for MediaPipe processing.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()

        session.startRunning()
        DispatchQueue.main.async { self.isRunning = true }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
// ────────────────────────────────────────────────────────────────────

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrame?(sampleBuffer)
    }
}
