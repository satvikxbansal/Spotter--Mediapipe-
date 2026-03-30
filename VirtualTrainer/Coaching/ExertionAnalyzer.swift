import Foundation
import Combine

// ────────────────────────────────────────────────────────────────────
// MARK: - ExertionAnalyzer
// ────────────────────────────────────────────────────────────────────

/// Derives a real-time exertion/effort score from facial blendshapes
/// produced by the FaceLandmarkerService.
///
/// ## Scoring Model
///
/// The analyzer combines multiple facial signals that correlate with
/// physical effort:
///
///   - **Brow furrow** (`browDownLeft/Right`): people frown harder
///     under load
///   - **Eye squint** (`eyeSquintLeft/Right`): involuntary squinting
///     during strain
///   - **Jaw clench** (inverse of `jawOpen`): clenching during
///     maximal effort
///   - **Mouth tension** (`mouthFunnel`, `mouthPucker`): bracing
///   - **Blink rate** (`eyeBlinkLeft/Right`): extended blinks or
///     heavy lids suggest fatigue
///
/// The score is exponentially smoothed to avoid frame-to-frame jitter.
///
/// ## Output
///
/// `effortScore`: 0.0 (relaxed) → 1.0 (maximum strain)
/// `fatigueLevel`: derived from sustained high effort + rising
///                  blink frequency over time
final class ExertionAnalyzer: ObservableObject {

    // MARK: - Published State

    /// Smoothed effort score: 0.0 (resting) to 1.0 (max strain).
    @Published private(set) var effortScore: Double = 0

    /// Fatigue indicator: 0.0 (fresh) to 1.0 (exhausted).
    @Published private(set) var fatigueLevel: Double = 0

    // MARK: - Configuration

    /// Exponential smoothing factor. Higher = more responsive but noisier.
    private let smoothingAlpha: Double = 0.25

    /// Weights for each blendshape signal in the effort composite.
    private let weights: [String: Double] = [
        "browDownLeft":    0.20,
        "browDownRight":   0.20,
        "eyeSquintLeft":   0.15,
        "eyeSquintRight":  0.15,
        "mouthFunnel":     0.10,
        "mouthPucker":     0.08,
        "jawOpen_inverse": 0.12,
    ]

    /// Fatigue accumulation rate per update when effort is high.
    private let fatigueAccumulationRate: Double = 0.002
    /// Fatigue recovery rate per update when effort is low.
    private let fatigueRecoveryRate: Double = 0.001
    /// Effort threshold above which fatigue accumulates.
    private let fatigueEffortThreshold: Double = 0.4

    // MARK: - Internal State

    private var rawEffort: Double = 0
    private var blinkHistory: [Date] = []
    private var lastBlinkState: Bool = false

    // MARK: - Public API

    /// Call every frame with the latest blendshape dictionary from
    /// `FaceLandmarkerService.blendshapes`.
    func update(blendshapes: [String: Float]) {
        guard !blendshapes.isEmpty else {
            rawEffort = rawEffort * 0.95
            effortScore = rawEffort
            return
        }

        var composite: Double = 0
        var totalWeight: Double = 0

        for (key, weight) in weights {
            if key == "jawOpen_inverse" {
                let jawOpen = Double(blendshapes["jawOpen"] ?? 0)
                let clench = max(0, 1.0 - jawOpen * 3.0)
                composite += clench * weight
            } else if let value = blendshapes[key] {
                composite += Double(value) * weight
            }
            totalWeight += weight
        }

        if totalWeight > 0 {
            composite /= totalWeight
        }

        let normalized = min(composite * 2.5, 1.0)

        rawEffort = rawEffort * (1.0 - smoothingAlpha) + normalized * smoothingAlpha
        effortScore = rawEffort

        trackBlinks(blendshapes: blendshapes)
        updateFatigue()
    }

    func reset() {
        rawEffort = 0
        effortScore = 0
        fatigueLevel = 0
        blinkHistory.removeAll()
        lastBlinkState = false
    }

    // MARK: - Blink Tracking

    private func trackBlinks(blendshapes: [String: Float]) {
        let leftBlink = blendshapes["eyeBlinkLeft"] ?? 0
        let rightBlink = blendshapes["eyeBlinkRight"] ?? 0
        let blinking = (leftBlink + rightBlink) / 2.0 > 0.5

        if blinking && !lastBlinkState {
            blinkHistory.append(Date())
            let cutoff = Date().addingTimeInterval(-30)
            blinkHistory.removeAll { $0 < cutoff }
        }
        lastBlinkState = blinking
    }

    // MARK: - Fatigue Model

    private func updateFatigue() {
        if effortScore > fatigueEffortThreshold {
            fatigueLevel = min(fatigueLevel + fatigueAccumulationRate, 1.0)
        } else {
            fatigueLevel = max(fatigueLevel - fatigueRecoveryRate, 0.0)
        }

        let blinkRate = Double(blinkHistory.count) / 30.0
        if blinkRate > 0.5 {
            fatigueLevel = min(fatigueLevel + 0.001, 1.0)
        }
    }
}
