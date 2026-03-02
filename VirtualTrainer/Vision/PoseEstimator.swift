import Vision
import CoreImage
import Combine
import os

// ────────────────────────────────────────────────────────────────────
// MARK: - PoseEstimator
// ────────────────────────────────────────────────────────────────────

/// Processes live video frames through Apple's Vision body-pose
/// pipeline and publishes joint positions ready for SwiftUI
/// consumption.
///
/// ## Coordinate Conversion
///
/// Vision returns points in a normalised coordinate space with a
/// **bottom-left** origin (like Core Graphics).  SwiftUI uses a
/// **top-left** origin.  Every point is flipped on output:
///
/// ```
/// swiftUIPoint = CGPoint(x: visionPoint.x, y: 1.0 - visionPoint.y)
/// ```
///
/// ## Threading
///
/// `processFrame(_:)` is designed to be called from the
/// `AVCaptureVideoDataOutputSampleBufferDelegate` callback, which
/// runs on its own serial queue.  The `bodyJoints` dictionary is
/// published back to the main thread for UI binding.
final class PoseEstimator: ObservableObject {

    // MARK: - Published State

    /// Every recognised joint mapped to its normalised position in
    /// SwiftUI's top-left coordinate space (0…1 on each axis).
    @Published var bodyJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

    /// Confidence of the best observation (0…1). Useful for hiding
    /// the skeleton overlay when tracking quality degrades.
    @Published var confidence: Float = 0

    // MARK: - Private

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VirtualTrainer",
        category: "PoseEstimator"
    )

    /// Minimum per-joint confidence to include in the output.
    /// Joints below this are noise and would jitter the overlay.
    private let jointConfidenceThreshold: Float = 0.1

    // MARK: - Frame Processing

    /// Run a single `VNDetectHumanBodyPoseRequest` against the
    /// provided pixel buffer and update `bodyJoints`.
    ///
    /// Call this from the capture-output delegate on its serial queue.
    /// The method is synchronous with respect to the Vision request;
    /// the published property update is dispatched to the main thread.
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanBodyPoseRequest()

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            logger.error("Vision request failed: \(error.localizedDescription)")
            return
        }

        guard
            let observation = request.results?.first
        else {
            DispatchQueue.main.async { [weak self] in
                self?.bodyJoints = [:]
                self?.confidence = 0
            }
            return
        }

        let recognizedPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]

        do {
            recognizedPoints = try observation.recognizedPoints(.all)
        } catch {
            logger.error("Failed to extract recognised points: \(error.localizedDescription)")
            return
        }

        // Build the converted dictionary, flipping Y for SwiftUI.
        var converted: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        converted.reserveCapacity(recognizedPoints.count)

        for (joint, point) in recognizedPoints where point.confidence > jointConfidenceThreshold {
            converted[joint] = CGPoint(
                x: point.location.x,
                y: 1.0 - point.location.y
            )
        }

        let topConfidence = observation.confidence

        DispatchQueue.main.async { [weak self] in
            self?.bodyJoints = converted
            self?.confidence = topConfidence
        }
    }
}
