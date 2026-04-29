import Foundation
import CoreGraphics
import simd

// ────────────────────────────────────────────────────────────────────
// MARK: - One Euro Filter
// ────────────────────────────────────────────────────────────────────

/// Adaptive low-pass filter for real-time pose landmarks.
///
/// The filter applies stronger smoothing when a landmark is still and relaxes
/// smoothing when velocity rises, which reduces overlay jitter without adding
/// as much lag as a fixed EMA during fast reps.
final class OneEuroFilter {
    private let minCutoff: Double
    private let beta: Double
    private let derivativeCutoff: Double

    private var previousValue: Double?
    private var previousDerivative: Double = 0
    private var previousTimestamp: TimeInterval?

    init(minCutoff: Double = 1.0, beta: Double = 0.007, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    func filter(_ value: Double, timestamp: TimeInterval) -> Double {
        guard let previousTimestamp, let previousValue else {
            self.previousTimestamp = timestamp
            self.previousValue = value
            previousDerivative = 0
            return value
        }

        let dt = max(timestamp - previousTimestamp, 1.0 / 120.0)
        let derivative = (value - previousValue) / dt
        let filteredDerivative = lowPass(
            current: derivative,
            previous: previousDerivative,
            alpha: alpha(cutoff: derivativeCutoff, dt: dt)
        )
        let cutoff = minCutoff + beta * abs(filteredDerivative)
        let filteredValue = lowPass(
            current: value,
            previous: previousValue,
            alpha: alpha(cutoff: cutoff, dt: dt)
        )

        self.previousTimestamp = timestamp
        self.previousValue = filteredValue
        previousDerivative = filteredDerivative
        return filteredValue
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    private func lowPass(current: Double, previous: Double, alpha: Double) -> Double {
        alpha * current + (1.0 - alpha) * previous
    }
}

final class LandmarkSmoother2D {
    private var filters: [JointName: (x: OneEuroFilter, y: OneEuroFilter)] = [:]

    func smooth(_ joints: [JointName: CGPoint], timestamp: TimeInterval) -> [JointName: CGPoint] {
        var smoothed: [JointName: CGPoint] = [:]
        smoothed.reserveCapacity(joints.count)

        for (joint, point) in joints {
            let pair = filters[joint] ?? (OneEuroFilter(), OneEuroFilter())
            filters[joint] = pair
            smoothed[joint] = CGPoint(
                x: CGFloat(pair.x.filter(Double(point.x), timestamp: timestamp)),
                y: CGFloat(pair.y.filter(Double(point.y), timestamp: timestamp))
            )
        }

        filters = filters.filter { joints[$0.key] != nil }
        return smoothed
    }

    func reset() {
        filters.removeAll()
    }
}

final class LandmarkSmoother3D {
    private var filters: [JointName: (x: OneEuroFilter, y: OneEuroFilter, z: OneEuroFilter)] = [:]

    func smooth(_ joints: [JointName: SIMD3<Float>], timestamp: TimeInterval) -> [JointName: SIMD3<Float>] {
        var smoothed: [JointName: SIMD3<Float>] = [:]
        smoothed.reserveCapacity(joints.count)

        for (joint, point) in joints {
            let triple = filters[joint] ?? (OneEuroFilter(), OneEuroFilter(), OneEuroFilter())
            filters[joint] = triple
            smoothed[joint] = SIMD3<Float>(
                Float(triple.x.filter(Double(point.x), timestamp: timestamp)),
                Float(triple.y.filter(Double(point.y), timestamp: timestamp)),
                Float(triple.z.filter(Double(point.z), timestamp: timestamp))
            )
        }

        filters = filters.filter { joints[$0.key] != nil }
        return smoothed
    }

    func reset() {
        filters.removeAll()
    }
}
