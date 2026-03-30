import MediaPipeTasksVision
import AVFoundation
import Combine
import os

// ────────────────────────────────────────────────────────────────────
// MARK: - FaceLandmarkerService
// ────────────────────────────────────────────────────────────────────

/// Processes live video frames through MediaPipe's Face Landmarker
/// pipeline and publishes 478 facial landmarks + 52 blendshape
/// coefficients.
///
/// ## Blendshapes
///
/// The blendshape scores (0.0–1.0) represent facial muscle
/// activations compatible with ARKit conventions:
///   - `browDownLeft/Right` — brow furrow
///   - `eyeSquintLeft/Right` — squinting / strain
///   - `jawOpen` — mouth opening (breathing proxy)
///   - `eyeBlinkLeft/Right` — blink / fatigue
///   - `mouthSmileLeft/Right` — positive engagement
///
/// ## Threading
///
/// Same model as `PoseEstimator`: `detectAsync` on capture queue,
/// delegate callback on MediaPipe's queue, publish to main.
final class FaceLandmarkerService: NSObject, ObservableObject {

    // MARK: - Published State

    /// Raw blendshape coefficients keyed by ARKit-compatible names.
    @Published var blendshapes: [String: Float] = [:]

    /// Whether a face is currently detected.
    @Published var faceDetected: Bool = false

    // MARK: - Private

    private var faceLandmarker: FaceLandmarker?
    private var timestampMs: Int = 0

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VirtualTrainer",
        category: "FaceLandmarker"
    )

    // MARK: - Init

    override init() {
        super.init()
        configureFaceLandmarker()
    }

    // MARK: - Configuration

    private func configureFaceLandmarker() {
        guard let modelPath = Bundle.main.path(
            forResource: "face_landmarker",
            ofType: "task"
        ) else {
            logger.info("face_landmarker.task not found — face features disabled")
            return
        }

        let options = FaceLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numFaces = 1
        options.minFaceDetectionConfidence = 0.5
        options.minFacePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.outputFaceBlendshapes = true
        options.faceLandmarkerLiveStreamDelegate = self

        do {
            faceLandmarker = try FaceLandmarker(options: options)
        } catch {
            logger.error("Failed to create FaceLandmarker: \(error.localizedDescription)")
        }
    }

    // MARK: - Frame Processing

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let faceLandmarker else { return }

        let currentTimestamp = Int(Date().timeIntervalSince1970 * 1000)
        guard currentTimestamp > timestampMs else { return }
        timestampMs = currentTimestamp

        guard let mpImage = try? MPImage(sampleBuffer: sampleBuffer) else { return }

        do {
            try faceLandmarker.detectAsync(
                image: mpImage,
                timestampInMilliseconds: timestampMs
            )
        } catch {
            logger.error("Face detection async failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Result Processing

    private func processResult(_ result: FaceLandmarkerResult?) {
        guard let result,
              !result.faceBlendshapes.isEmpty,
              let firstFace = result.faceBlendshapes.first else {
            DispatchQueue.main.async { [weak self] in
                self?.blendshapes = [:]
                self?.faceDetected = false
            }
            return
        }

        var shapes: [String: Float] = [:]
        shapes.reserveCapacity(firstFace.categories.count)

        for category in firstFace.categories {
            if let name = category.categoryName {
                shapes[name] = category.score
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.blendshapes = shapes
            self?.faceDetected = true
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - FaceLandmarkerLiveStreamDelegate
// ────────────────────────────────────────────────────────────────────

extension FaceLandmarkerService: FaceLandmarkerLiveStreamDelegate {
    func faceLandmarker(
        _ faceLandmarker: FaceLandmarker,
        didFinishDetection result: FaceLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        if let error {
            logger.error("Face landmarker error: \(error.localizedDescription)")
        }
        processResult(result)
    }
}
