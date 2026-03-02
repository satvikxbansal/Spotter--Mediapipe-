import CoreHaptics
import UIKit

// ────────────────────────────────────────────────────────────────────
// MARK: - HapticsEngine
// ────────────────────────────────────────────────────────────────────

/// Singleton haptic engine for the Virtual Trainer.
///
/// Uses CoreHaptics for fully authored waveforms (intensity curves,
/// sharpness, precise timing) on supported devices. Falls back to
/// UIFeedbackGenerator on older hardware so the app never crashes
/// or silently does nothing.
///
/// Call sites:
/// ```
/// HapticsEngine.shared.repTick()
/// HapticsEngine.shared.successRipple()
/// ```
final class HapticsEngine {

    static let shared = HapticsEngine()

    // CoreHaptics engine — nil on unsupported devices.
    private var engine: CHHapticEngine?
    private let supportsHaptics: Bool

    // UIKit fallback generators (pre-warmed).
    private let rigidImpact  = UIImpactFeedbackGenerator(style: .rigid)
    private let lightImpact  = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    // MARK: Init

    private init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        if supportsHaptics { createEngine() }
        prepareGenerators()
    }

    // MARK: - Engine Lifecycle

    private func createEngine() {
        do {
            engine = try CHHapticEngine()
            engine?.isAutoShutdownEnabled = true

            // Re-create on reset (e.g., after app returns from background).
            engine?.resetHandler = { [weak self] in
                self?.restartEngine()
            }

            // Silently handle external stop (system resource pressure).
            engine?.stoppedHandler = { _ in }

            try engine?.start()
        } catch {
            engine = nil
        }
    }

    private func restartEngine() {
        do {
            try engine?.start()
        } catch {
            engine = nil
        }
    }

    private func prepareGenerators() {
        rigidImpact.prepare()
        lightImpact.prepare()
        notification.prepare()
    }

    // MARK: - Public API

    /// A completed rep. Sharp, authoritative, percussive.
    ///
    /// CoreHaptics pattern: a single transient event at max intensity
    /// and high sharpness — the tightest "click" the Taptic Engine can
    /// produce, far crisper than UIFeedbackGenerator's canned `.rigid`.
    func repTick() {
        guard supportsHaptics, let engine else {
            rigidImpact.impactOccurred(intensity: 1.0)
            rigidImpact.prepare()
            return
        }

        let sharpTap = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.95)
            ],
            relativeTime: 0
        )

        playPattern([sharpTap], on: engine)
    }

    /// Standard button press. Light, crisp, barely there.
    func buttonTap() {
        guard supportsHaptics, let engine else {
            lightImpact.impactOccurred(intensity: 0.5)
            lightImpact.prepare()
            return
        }

        let softTap = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
            ],
            relativeTime: 0
        )

        playPattern([softTap], on: engine)
    }

    /// Form deviation or camera tracking lost.
    ///
    /// Two rapid transient pulses (120ms apart), medium intensity,
    /// low sharpness — feels like a muffled double-knock, urgent but
    /// not aggressive. Distinctly different from the sharp `repTick`.
    func warningPulse() {
        guard supportsHaptics, let engine else {
            notification.notificationOccurred(.warning)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.notification.notificationOccurred(.warning)
                self?.notification.prepare()
            }
            return
        }

        let pulse1 = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.75),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.30)
            ],
            relativeTime: 0
        )

        let pulse2 = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.90),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.40)
            ],
            relativeTime: 0.12
        )

        playPattern([pulse1, pulse2], on: engine)
    }

    /// Set / workout complete. A rising three-beat ripple.
    ///
    /// Each hit is heavier and sharper than the last, creating an
    /// ascending crescendo — the physical equivalent of a finish-line
    /// horn. Total duration ~400ms.
    func successRipple() {
        guard supportsHaptics, let engine else {
            notification.notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.rigidImpact.impactOccurred(intensity: 0.7)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.rigidImpact.impactOccurred(intensity: 1.0)
                self?.rigidImpact.prepare()
            }
            notification.prepare()
            return
        }

        let beat1 = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.40)
            ],
            relativeTime: 0
        )

        let beat2 = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.72),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.60)
            ],
            relativeTime: 0.14
        )

        let beat3 = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.90)
            ],
            relativeTime: 0.34
        )

        // Sustained low rumble underneath the beats for body.
        let rumble = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.30),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.10)
            ],
            relativeTime: 0,
            duration: 0.42
        )

        playPattern([beat1, beat2, beat3, rumble], on: engine)
    }

    // MARK: - Internal

    private func playPattern(_ events: [CHHapticEvent], on engine: CHHapticEngine) {
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Engine died mid-session — restart and swallow the missed haptic.
            restartEngine()
        }
    }
}
