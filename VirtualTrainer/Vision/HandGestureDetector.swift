import Foundation
import MediaPipeTasksVision
import AVFoundation
import Combine
import os

// ────────────────────────────────────────────────────────────────────
// MARK: - Hand Gesture
// ────────────────────────────────────────────────────────────────────

enum HandGesture: String, Equatable {
    case thumbsUp
    case thumbsDown
    case openPalm
    case fist
    case victory
    case pointingUp
    case none
}

// ────────────────────────────────────────────────────────────────────
// MARK: - HandGestureDetector
// ────────────────────────────────────────────────────────────────────

/// Detects hand gestures from live video frames using MediaPipe's
/// `GestureRecognizer` task.
///
/// The GestureRecognizer provides ML-based gesture classification
/// directly (Thumb_Up, Thumb_Down, Open_Palm, Closed_Fist, Victory,
/// Pointing_Up, ILoveYou) rather than requiring manual heuristic
/// analysis of raw landmarks.
///
/// ## Accuracy Strategy
///
/// Evidence accumulation: a gesture must be detected for
/// `confirmationFrames` consecutive frames before it's promoted
/// to a confirmed result. This prevents single-frame jitter.
///
/// ## Fallback
///
/// If the `gesture_recognizer.task` model is not bundled, the
/// detector falls back to the `hand_landmarker.task` with manual
/// gesture classification (the previous approach).
final class HandGestureDetector: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentGesture: HandGesture = .none
    @Published private(set) var raisedFingerCount: Int = 0
    @Published private(set) var handConfidence: Float = 0
    @Published private(set) var handDetected: Bool = false
    @Published private(set) var allHandLandmarks: [[Int: CGPoint]] = []

    // MARK: - Hand Skeleton Topology

    /// MediaPipe 21-point hand skeleton connections.
    static let handBonePairs: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4),
        (0, 5), (5, 6), (6, 7), (7, 8),
        (0, 9), (9, 10), (10, 11), (11, 12),
        (0, 13), (13, 14), (14, 15), (15, 16),
        (0, 17), (17, 18), (18, 19), (19, 20),
        (5, 9), (9, 13), (13, 17),
    ]

    // MARK: - Configuration

    private let confirmationFrames: Int = 3

    // MARK: - Internal State

    private var candidateGesture: HandGesture = .none
    private var candidateCount: Int = 0

    private var gestureRecognizer: GestureRecognizer?
    private var handLandmarker: HandLandmarker?
    private var usingGestureRecognizer = false
    private var timestampMs: Int = 0

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VirtualTrainer",
        category: "HandGesture"
    )

    // Fallback heuristic thresholds (only used when gesture_recognizer.task is absent)
    private let curlThreshold: Double = 0.12

    // MARK: - Init

    override init() {
        super.init()
        configureDetector()
    }

    // MARK: - Configuration

    private func configureDetector() {
        if let grPath = Bundle.main.path(forResource: "gesture_recognizer", ofType: "task") {
            configureGestureRecognizer(modelPath: grPath)
        } else if let hlPath = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") {
            logger.info("gesture_recognizer.task not found — falling back to hand_landmarker")
            configureHandLandmarkerFallback(modelPath: hlPath)
        } else {
            logger.error("No hand/gesture model found in bundle")
        }
    }

    private func configureGestureRecognizer(modelPath: String) {
        let options = GestureRecognizerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numHands = 2
        options.minHandDetectionConfidence = 0.5
        options.minHandPresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.gestureRecognizerLiveStreamDelegate = self

        do {
            gestureRecognizer = try GestureRecognizer(options: options)
            usingGestureRecognizer = true
        } catch {
            logger.error("Failed to create GestureRecognizer: \(error.localizedDescription)")
            if let hlPath = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") {
                configureHandLandmarkerFallback(modelPath: hlPath)
            }
        }
    }

    private func configureHandLandmarkerFallback(modelPath: String) {
        let options = HandLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numHands = 2
        options.minHandDetectionConfidence = 0.5
        options.minHandPresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.handLandmarkerLiveStreamDelegate = self

        do {
            handLandmarker = try HandLandmarker(options: options)
            usingGestureRecognizer = false
        } catch {
            logger.error("Failed to create HandLandmarker fallback: \(error.localizedDescription)")
        }
    }

    // MARK: - Frame Processing

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        let currentTimestamp = Int(Date().timeIntervalSince1970 * 1000)
        guard currentTimestamp > timestampMs else { return }
        timestampMs = currentTimestamp

        guard let mpImage = try? MPImage(sampleBuffer: sampleBuffer) else { return }

        do {
            if usingGestureRecognizer, let gr = gestureRecognizer {
                try gr.recognizeAsync(image: mpImage, timestampInMilliseconds: timestampMs)
            } else if let hl = handLandmarker {
                try hl.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
            }
        } catch {
            logger.error("Hand/gesture detection async failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        candidateGesture = .none
        candidateCount = 0
        DispatchQueue.main.async { [weak self] in
            self?.currentGesture = .none
            self?.raisedFingerCount = 0
            self?.handConfidence = 0
            self?.handDetected = false
            self?.allHandLandmarks = []
        }
    }

    // MARK: - GestureRecognizer Result Processing

    private func processGestureResult(_ result: GestureRecognizerResult?) {
        guard let result, !result.landmarks.isEmpty else {
            clearDetection()
            return
        }

        let allHands = extractLandmarks(from: result.landmarks)

        let gesture = mapMediaPipeGesture(result.gestures)
        let conf = result.gestures.first?.first?.score ?? 0

        updateWithCandidate(gesture, confidence: conf, allHands: allHands)
    }

    /// Maps MediaPipe's category labels to our `HandGesture` enum.
    private func mapMediaPipeGesture(_ gestures: [[ResultCategory]]) -> HandGesture {
        guard let top = gestures.first?.first else { return .none }

        switch top.categoryName {
        case "Thumb_Up":    return .thumbsUp
        case "Thumb_Down":  return .thumbsDown
        case "Open_Palm":   return .openPalm
        case "Closed_Fist": return .fist
        case "Victory":     return .victory
        case "Pointing_Up": return .pointingUp
        default:            return .none
        }
    }

    // MARK: - HandLandmarker Fallback Result Processing

    private func processHandLandmarkerResult(_ result: HandLandmarkerResult?) {
        guard let result, !result.landmarks.isEmpty else {
            clearDetection()
            return
        }

        let allHands = extractLandmarks(from: result.landmarks)

        guard let firstHand = result.landmarks.first, firstHand.count >= 21 else {
            clearDetection()
            return
        }

        let points = firstHand.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        let gesture = analyzeHandPoseFallback(points)
        let conf = Float(firstHand.first?.visibility?.floatValue ?? 0.8)

        updateWithCandidate(gesture, confidence: conf, allHands: allHands)
    }

    // MARK: - Shared Helpers

    private func extractLandmarks(from landmarkSets: [[NormalizedLandmark]]) -> [[Int: CGPoint]] {
        var allHands: [[Int: CGPoint]] = []
        allHands.reserveCapacity(landmarkSets.count)

        for handLandmarks in landmarkSets {
            guard handLandmarks.count >= 21 else { continue }
            var dict: [Int: CGPoint] = [:]
            dict.reserveCapacity(21)
            for (i, lm) in handLandmarks.enumerated() {
                dict[i] = CGPoint(x: CGFloat(lm.x), y: CGFloat(lm.y))
            }
            allHands.append(dict)
        }
        return allHands
    }

    // MARK: - Evidence Accumulation

    private func updateWithCandidate(
        _ gesture: HandGesture,
        confidence: Float,
        allHands: [[Int: CGPoint]]
    ) {
        if gesture == candidateGesture {
            candidateCount += 1
        } else {
            candidateGesture = gesture
            candidateCount = 1
        }

        let confirmed: Bool
        if gesture == .thumbsUp || gesture == .thumbsDown {
            confirmed = candidateCount >= confirmationFrames
        } else {
            confirmed = candidateCount >= max(confirmationFrames - 1, 2)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.allHandLandmarks = allHands

            if confirmed {
                if self.currentGesture != gesture {
                    self.currentGesture = gesture
                }
                self.handConfidence = confidence
                self.handDetected = true
            }
        }
    }

    private func clearDetection() {
        candidateGesture = .none
        candidateCount = 0

        DispatchQueue.main.async { [weak self] in
            self?.handDetected = false
            self?.handConfidence = 0
            if self?.currentGesture != .none {
                self?.currentGesture = .none
            }
            self?.raisedFingerCount = 0
            self?.allHandLandmarks = []
        }
    }

    // MARK: - Fallback Heuristic Gesture Analysis

    private func analyzeHandPoseFallback(_ points: [CGPoint]) -> HandGesture {
        let wrist     = points[0]
        let thumbCMC  = points[1]
        let thumbTip  = points[4]
        let indexTip  = points[8]
        let indexMCP  = points[5]
        let middleTip = points[12]
        let middleMCP = points[9]
        let ringTip   = points[16]
        let ringMCP   = points[13]
        let littleTip = points[20]
        let littleMCP = points[17]

        let handSize = distance(wrist, middleMCP)
        let fingerTipYs = [indexTip.y, middleTip.y, ringTip.y, littleTip.y]
        let thumbY = thumbTip.y
        let verticalDelta = wrist.y - thumbY
        let threshold = max(handSize * 0.3, 0.02)

        if verticalDelta > threshold {
            if fingerTipYs.allSatisfy({ thumbY < $0 + threshold * 0.3 }) {
                return .thumbsUp
            }
        } else if verticalDelta < -threshold {
            if fingerTipYs.allSatisfy({ thumbY > $0 - threshold * 0.3 }) {
                return .thumbsDown
            }
        }

        let curled = [
            isCurled(tip: indexTip, mcp: indexMCP),
            isCurled(tip: middleTip, mcp: middleMCP),
            isCurled(tip: ringTip, mcp: ringMCP),
            isCurled(tip: littleTip, mcp: littleMCP),
        ]

        if curled.allSatisfy({ $0 }) { return .fist }
        if curled.allSatisfy({ !$0 }) { return .openPalm }

        return .none
    }

    private func isCurled(tip: CGPoint, mcp: CGPoint) -> Bool {
        distance(tip, mcp) < curlThreshold
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - GestureRecognizerLiveStreamDelegate
// ────────────────────────────────────────────────────────────────────

extension HandGestureDetector: GestureRecognizerLiveStreamDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: GestureRecognizer,
        didFinishGestureRecognition result: GestureRecognizerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        if let error {
            logger.error("Gesture recognizer error: \(error.localizedDescription)")
        }
        processGestureResult(result)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - HandLandmarkerLiveStreamDelegate (fallback)
// ────────────────────────────────────────────────────────────────────

extension HandGestureDetector: HandLandmarkerLiveStreamDelegate {
    func handLandmarker(
        _ handLandmarker: HandLandmarker,
        didFinishDetection result: HandLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        if let error {
            logger.error("Hand landmarker error: \(error.localizedDescription)")
        }
        processHandLandmarkerResult(result)
    }
}
