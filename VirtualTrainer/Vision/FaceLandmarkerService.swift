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
    private var timestampMs: Int = -250
    private var isProcessingFrame = false
    private var activeFrameTimestampMs: Int?
    private var activeFrameGeneration: UInt64?
    private var processingGeneration: UInt64 = 0
    private let stateLock = NSLock()
    private let minimumFrameIntervalMs = 250
    private let frameTimeoutSeconds: TimeInterval = 1.0

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

    func reset() {
        stateLock.lock()
        processingGeneration &+= 1
        let generation = processingGeneration
        timestampMs = -minimumFrameIntervalMs
        isProcessingFrame = false
        activeFrameTimestampMs = nil
        activeFrameGeneration = nil
        stateLock.unlock()

        clearDetection(for: generation)
    }

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let faceLandmarker else { return }

        let currentTimestamp = sampleTimestampMilliseconds(sampleBuffer)
        guard reserveFrame(timestampInMilliseconds: currentTimestamp) else { return }

        guard let mpImage = try? MPImage(sampleBuffer: sampleBuffer) else {
            completeFrame()
            return
        }

        do {
            try faceLandmarker.detectAsync(
                image: mpImage,
                timestampInMilliseconds: currentTimestamp
            )
        } catch {
            completeFrame(timestampInMilliseconds: currentTimestamp)
            logger.error("Face detection async failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Result Processing

    private func processResult(_ result: FaceLandmarkerResult?, frameGeneration: UInt64) {
        guard let result,
              !result.faceBlendshapes.isEmpty,
              let firstFace = result.faceBlendshapes.first else {
            publishDetection(for: frameGeneration) { [weak self] in
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

        publishDetection(for: frameGeneration) { [weak self] in
            self?.blendshapes = shapes
            self?.faceDetected = true
        }
    }

    private func sampleTimestampMilliseconds(_ sampleBuffer: CMSampleBuffer) -> Int {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let seconds = CMTimeGetSeconds(pts)
        if seconds.isFinite && seconds >= 0 {
            return Int(seconds * 1000.0)
        }
        return Int(Date().timeIntervalSince1970 * 1000)
    }

    private func reserveFrame(timestampInMilliseconds currentTimestamp: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isProcessingFrame else { return false }
        guard currentTimestamp > timestampMs else { return false }
        guard currentTimestamp - timestampMs >= minimumFrameIntervalMs else { return false }

        isProcessingFrame = true
        activeFrameTimestampMs = currentTimestamp
        activeFrameGeneration = processingGeneration
        timestampMs = currentTimestamp
        scheduleFrameTimeout(timestampInMilliseconds: currentTimestamp)
        return true
    }

    private func completeFrame(timestampInMilliseconds completedTimestamp: Int? = nil) {
        stateLock.lock()
        defer { stateLock.unlock() }

        if let completedTimestamp,
           activeFrameTimestampMs != completedTimestamp {
            return
        }

        isProcessingFrame = false
        activeFrameTimestampMs = nil
        activeFrameGeneration = nil
    }

    private func finishFrame(timestampInMilliseconds completedTimestamp: Int) -> UInt64? {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard activeFrameTimestampMs == completedTimestamp,
              let generation = activeFrameGeneration
        else { return nil }
        isProcessingFrame = false
        activeFrameTimestampMs = nil
        activeFrameGeneration = nil
        return generation
    }

    private func scheduleFrameTimeout(timestampInMilliseconds submittedTimestamp: Int) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + frameTimeoutSeconds) { [weak self] in
            self?.expireFrameIfNeeded(timestampInMilliseconds: submittedTimestamp)
        }
    }

    private func expireFrameIfNeeded(timestampInMilliseconds expiredTimestamp: Int) {
        stateLock.lock()
        let didExpire = isProcessingFrame && activeFrameTimestampMs == expiredTimestamp
        if didExpire {
            isProcessingFrame = false
            activeFrameTimestampMs = nil
            activeFrameGeneration = nil
        }
        stateLock.unlock()

        if didExpire {
            logger.warning("Face detection timed out for frame \(expiredTimestamp); clearing stale effort state")
            clearDetection()
        }
    }

    private func clearDetection(for generation: UInt64? = nil) {
        publishDetection(for: generation) { [weak self] in
            self?.blendshapes = [:]
            self?.faceDetected = false
        }
    }

    private func publishDetection(
        for generation: UInt64?,
        update: @escaping () -> Void
    ) {
        let guardedUpdate = { [weak self] in
            guard let self else { return }
            if let generation,
               !self.isCurrentGeneration(generation) {
                return
            }
            update()
        }

        if Thread.isMainThread {
            guardedUpdate()
        } else {
            DispatchQueue.main.async(execute: guardedUpdate)
        }
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        stateLock.lock()
        let isCurrent = processingGeneration == generation
        stateLock.unlock()
        return isCurrent
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
        guard let frameGeneration = finishFrame(timestampInMilliseconds: timestampInMilliseconds) else { return }

        if let error {
            logger.error("Face landmarker error: \(error.localizedDescription)")
        }
        processResult(result, frameGeneration: frameGeneration)
    }
}
