import MediaPipeTasksVision
import AVFoundation
import Combine
import simd
import os

// ────────────────────────────────────────────────────────────────────
// MARK: - PoseEstimator
// ────────────────────────────────────────────────────────────────────

/// Processes live video frames through Google MediaPipe's Pose
/// Landmarker pipeline and publishes joint positions ready for
/// SwiftUI consumption.
///
/// ## Coordinate Space
///
/// MediaPipe returns landmarks in normalised coordinates (0…1)
/// with a **top-left** origin, which matches SwiftUI's coordinate
/// system directly — no Y-flip needed.
///
/// ## World Landmarks
///
/// In addition to 2D normalized coordinates, MediaPipe outputs
/// real-world 3D coordinates in meters with the hip midpoint as
/// origin. These are camera-independent and give accurate angles
/// for exercises where depth matters (squats, lunges, presses).
///
/// ## Segmentation Mask
///
/// When enabled, the Pose Landmarker also outputs a per-pixel
/// body segmentation mask alongside the landmarks. This is used
/// for visual effects like background blur and body highlighting.
///
/// ## Threading
///
/// `processFrame(_:)` is called from the AVCaptureSession's video
/// output queue. MediaPipe's `detectAsync` processes the frame
/// asynchronously and delivers results via the livestream delegate
/// on a serial queue. Published properties are dispatched to main.
///
/// ## 33 Landmarks + Synthetic Joints
///
/// MediaPipe outputs 33 body landmarks (indices 0–32). Two
/// additional synthetic joints are computed:
///   - `neck`: midpoint of left shoulder (11) + right shoulder (12)
///   - `root`: midpoint of left hip (23) + right hip (24)
final class PoseEstimator: NSObject, ObservableObject {

    // MARK: - Published State

    /// 2D normalized landmarks for overlay rendering.
    @Published var bodyJoints: [JointName: CGPoint] = [:]

    /// 3D world landmarks in meters (hip-center origin) for angle calculations.
    @Published var worldJoints: [JointName: SIMD3<Float>] = [:]

    @Published var confidence: Float = 0

    /// Body segmentation mask dimensions + float data from the pose landmarker.
    /// Nil when no pose is detected or segmentation is unavailable.
    @Published var segmentationMask: SegmentationMaskData?

    // MARK: - Private

    private var poseLandmarker: PoseLandmarker?
    private var timestampMs: Int = 0

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VirtualTrainer",
        category: "PoseEstimator"
    )

    /// Minimum per-landmark visibility to include in output.
    private let visibilityThreshold: Float = 0.5

    // MARK: - Init

    override init() {
        super.init()
        configurePoseLandmarker()
    }

    // MARK: - Configuration

    private func configurePoseLandmarker() {
        guard let modelPath = Bundle.main.path(
            forResource: "pose_landmarker_full",
            ofType: "task"
        ) else {
            logger.error("pose_landmarker_full.task not found in bundle")
            return
        }

        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.shouldOutputSegmentationMasks = true
        options.poseLandmarkerLiveStreamDelegate = self

        do {
            poseLandmarker = try PoseLandmarker(options: options)
        } catch {
            logger.error("Failed to create PoseLandmarker: \(error.localizedDescription)")
        }
    }

    // MARK: - Frame Processing

    /// Feed a camera sample buffer into MediaPipe for async detection.
    /// Call from the capture-output delegate on its serial queue.
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let poseLandmarker else { return }

        let currentTimestamp = Int(Date().timeIntervalSince1970 * 1000)
        guard currentTimestamp > timestampMs else { return }
        timestampMs = currentTimestamp

        guard let mpImage = try? MPImage(sampleBuffer: sampleBuffer) else {
            logger.error("Failed to create MPImage from sample buffer")
            return
        }

        do {
            try poseLandmarker.detectAsync(
                image: mpImage,
                timestampInMilliseconds: timestampMs
            )
        } catch {
            logger.error("Pose detection async failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Result Processing

    private func processResult(_ result: PoseLandmarkerResult?) {
        guard let result,
              let landmarks = result.landmarks.first,
              !landmarks.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.bodyJoints = [:]
                self?.worldJoints = [:]
                self?.confidence = 0
                self?.segmentationMask = nil
            }
            return
        }

        // --- 2D normalized landmarks (for overlay rendering) ---
        var converted2D: [JointName: CGPoint] = [:]
        converted2D.reserveCapacity(35)

        for (index, landmark) in landmarks.enumerated() {
            guard landmark.visibility?.floatValue ?? 0 > visibilityThreshold,
                  let joint = JointName(rawValue: index) else { continue }
            converted2D[joint] = CGPoint(x: CGFloat(landmark.x), y: CGFloat(landmark.y))
        }

        // --- 3D world landmarks (for accurate angle math) ---
        var converted3D: [JointName: SIMD3<Float>] = [:]
        converted3D.reserveCapacity(35)

        if let worldLandmarks = result.worldLandmarks.first {
            for (index, wl) in worldLandmarks.enumerated() {
                guard let joint = JointName(rawValue: index) else { continue }
                let vis = landmarks[safe: index]?.visibility?.floatValue ?? 0
                guard vis > visibilityThreshold else { continue }
                converted3D[joint] = SIMD3<Float>(wl.x, wl.y, wl.z)
            }
        }

        // Synthetic joints — 2D
        if let ls = converted2D[.leftShoulder], let rs = converted2D[.rightShoulder] {
            converted2D[.neck] = CGPoint(
                x: (ls.x + rs.x) / 2,
                y: (ls.y + rs.y) / 2
            )
        }
        if let lh = converted2D[.leftHip], let rh = converted2D[.rightHip] {
            converted2D[.root] = CGPoint(
                x: (lh.x + rh.x) / 2,
                y: (lh.y + rh.y) / 2
            )
        }

        // Synthetic joints — 3D
        if let ls = converted3D[.leftShoulder], let rs = converted3D[.rightShoulder] {
            converted3D[.neck] = (ls + rs) / 2
        }
        if let lh = converted3D[.leftHip], let rh = converted3D[.rightHip] {
            converted3D[.root] = (lh + rh) / 2
        }

        // --- Segmentation mask ---
        var maskData: SegmentationMaskData?
        if let firstMask = result.segmentationMasks.first {
            let w = Int(firstMask.width)
            let h = Int(firstMask.height)
            let count = w * h
            if count > 0 {
                let srcPtr = firstMask.float32Data
                let copied = Array(UnsafeBufferPointer(start: srcPtr, count: count))
                maskData = SegmentationMaskData(width: w, height: h, data: copied)
            }
        }

        let topConfidence = landmarks.first?.visibility?.floatValue ?? 0

        DispatchQueue.main.async { [weak self] in
            self?.bodyJoints = converted2D
            self?.worldJoints = converted3D
            self?.confidence = topConfidence
            self?.segmentationMask = maskData
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - PoseLandmarkerLiveStreamDelegate
// ────────────────────────────────────────────────────────────────────

extension PoseEstimator: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        if let error {
            logger.error("Pose landmarker error: \(error.localizedDescription)")
        }
        processResult(result)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - SegmentationMaskData
// ────────────────────────────────────────────────────────────────────

/// Lightweight snapshot of the segmentation mask produced by
/// PoseLandmarker. Copies the float32 confidence values so the
/// data outlives MediaPipe's internal C++ buffer.
struct SegmentationMaskData {
    let width: Int
    let height: Int
    /// Row-major float32 confidence values (0.0 = background, 1.0 = person).
    let data: [Float]
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Collection Safe Subscript
// ────────────────────────────────────────────────────────────────────

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
