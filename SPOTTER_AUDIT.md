# Spotter — Deep Biomechanics & Pose-Engine Audit
*Goal: ship the best exercise-detection engine in the world.*
Date: 2026-04-29 · Scope: full `VirtualTrainer/` Swift module · MediaPipe Pose Landmarker (Full)

---

## 0 · Executive Summary

Spotter is structurally further along than most "AI form coach" prototypes you'll see. The exercise model is data-driven (every exercise is an `ExerciseDefinition` of angles + thresholds + form rules + positional checks), the rep counter is a single universal state machine that any exercise can plug into, and the form-feedback engine is a prioritized cascade with cooldowns. That bones-and-skin architecture is correct.

But the engine is leaving a lot on the table:

1. **MediaPipe is being run on its defaults.** CPU delegate, default 0.5 thresholds, no smoothing on rendered landmarks, no orientation hints, raw timestamps. There is at least 30–40% latency and visual quality on the floor.
2. **The "biomechanics" layer is a single point of measurement (peak angle at the bottom of the rep).** It does not capture velocity, acceleration, eccentric/concentric tempo, bar-path symmetry, or any per-rep telemetry. The data needed to actually be the best in the world *is computed and discarded each rep*.
3. **The voice coach is a no-op stub.** `VoiceCoachManager` returns immediately on every call. Every "personality" string in the library is being thrown into a banner only.
4. **`SquatRepCounter.swift` is dead code.** It carries divergent thresholds, no EMA, no min-rep gating, and a labeling bug. It needs to be removed before someone wires it back up.
5. **Several exercises have biomechanically unusual or wrong-direction thresholds.** Most concerning: `frontRaises.formRules.frontrise_sway` is gated on hip→shoulder→knee with `minAngle: 165` — but that vector orientation makes the value range non-obvious; lunges use `.bestAvailable` which silently picks the right side regardless of which leg is forward; the deadlift has no spine-flexion check despite advertising "back rounding" in copy.
6. **Two systemic bugs in `AngleCalculator.swift`:** `hip_center` and `shoulder_center` resolve to *one side*, not the midpoint (so `legAbductionAngle` and `armLineAngle` are silently mis-anchored), and `bodyLineAngle` duplicates `hipFlexionAngle` (same triple, different key).
7. **Camera is mirrored at the AV connection but landmark "left/right" labels are not remapped.** Coaching that says "your left knee" is anatomically the user's right, and vice versa. The `kneeValgus` math has hand-tuned signs that compensate, but the drift from this is unprincipled.
8. **The library has 30 exercises but only ~6 of them are competently spec'd.** Squats, push-ups, lunges, glute bridge, plank, deadlift get serious form rules. The rest are mostly two-rule wrappers and miss obvious cues (e.g. the bicep curl has nothing checking the body lean, jumping jacks has no foot-symmetry, mountain climbers has no per-knee tracking, deadlift has no thoracic-rounding check, etc.).
9. **Yoga is two poses.** That entire category is a placeholder.

Despite all that — the bones are good. The `ExerciseDefinition` schema is the right schema. With a focused two-month effort you can credibly claim best-in-class on iOS.

The rest of this document is the long version.

---

## 1 · Architecture: how the engine is wired

```
CameraManager (AVCaptureSession, 30fps front cam, mirrored)
     │  CMSampleBuffer
     ▼
PoseEstimator  (MediaPipe Pose Landmarker Full, .liveStream, CPU)
     │  bodyJoints (2D normalized, 33+2 synthetic)
     │  worldJoints (3D meters, hip-origin)
     │  segmentationMask (Float[])
     ▼
TrainerSessionView (the one screen that owns the lifecycle)
     ├── TrainerOverlayView    — Canvas-based skeleton + angle arcs
     ├── BodyVisibilityChecker — per-exercise required joints check
     ├── FramePositionAnalyzer — segmentation-mask centering check
     ├── UniversalRepCounter   — angle EMA → state machine → rep count + form score
     ├── FormFeedbackEngine    — prioritized cue cascade (cooldowns)
     ├── HandGestureDetector   — thumbs up / thumbs down → ready/retry
     ├── FaceLandmarkerService — *exists but barely used*
     ├── ExertionAnalyzer      — fatigue baseline (post-ready only)
     ├── MotivationEngine      — banner copy generator
     ├── VoiceCoachManager     — *no-op stub*
     └── WorkoutReadyCoordinator — positioning → askingReady → countdown(3..1)
```

### Strengths
- **Data-driven exercise spec** (`ExerciseDefinition` is one source of truth — angle defs, thresholds, rules, ideal angles, tempo range all live in one struct).
- **Phase-based feedback gating** (`activeDuringPhases`) means cues only fire when biomechanically relevant.
- **Cooldown system in `FormFeedbackEngine`** prevents "nag-storms" (per-rule + global 3-second gate).
- **Synthetic neck/root joints** are computed and exposed (`PoseEstimator.swift:176–195`).
- **Clean SwiftUI/Canvas overlay** with no UIKit baggage.

### Weaknesses (high level — details below)
- All inference and rendering is CPU-bound. No GPU delegate enabled.
- `bodyJoints` are not smoothed; the visible skeleton jitters frame-to-frame.
- No bilateral telemetry persisted (per-rep angle traces lost on each rep).
- No FPS budget instrumentation. No drop-frame counter. No latency probe.
- No A/B harness for threshold tuning.
- `VoiceCoachManager` is a placeholder; the entire personality system has no voice.

---

## 2 · MediaPipe Implementation — what's wrong, what's missing

### 2.1 Configuration audit

| Setting | Current | Industry / docs recommendation | Verdict |
|---|---|---|---|
| Model | `pose_landmarker_full.task` | Full for live; consider Heavy for replay | OK |
| Delegate | **default (CPU)** | GPU on iPhone for ≥2× FPS, lower thermals | **Should change** |
| Running mode | `.liveStream` | Correct for camera feed | OK |
| `minPoseDetectionConfidence` | 0.5 (default) | 0.6–0.7 in fitness apps to avoid background false positives | Tune |
| `minTrackingConfidence` | 0.5 | 0.5 — keep low to avoid mid-rep tracker resets | OK |
| `minPosePresenceConfidence` | 0.5 | 0.5 | OK |
| `numPoses` | 1 | 1 | OK |
| `shouldOutputSegmentationMasks` | true | true (used for framing analyzer) | OK |
| Per-landmark visibility gate | 0.5 | 0.5 raw use, ≥0.7 for graded metrics | Tune |
| Timestamp source | `Date().timeIntervalSince1970 * 1000` | `CMSampleBuffer` PTS in ms | **Bug source** |

### 2.2 Concrete fixes

**A. Enable GPU delegate.** On iPhone 12 and newer, GPU inference roughly doubles Pose Landmarker Full's throughput vs CPU and substantially lowers sustained thermals during a 30-min session.
```swift
let baseOptions = BaseOptions()
baseOptions.modelAssetPath = modelPath
baseOptions.delegate = .GPU       // <— add this everywhere
options.baseOptions = baseOptions
```
Apply this in `PoseEstimator.swift`, `FaceLandmarkerService.swift`, and `HandGestureDetector.swift`. Add a runtime fallback to `.CPU` on simulator (Metal sim path is flaky).

**B. Use the sample buffer PTS, not wall clock.** At 30 fps two consecutive frames can land in the same millisecond when scheduled on a busy queue. The current code (`PoseEstimator.swift:118–120`) drops the second one silently:
```swift
guard timestamp > timestampMs else { return }
```
Replace with:
```swift
let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
let timestampMs = Int(CMTimeGetSeconds(pts) * 1000.0)
```
This is cheaper, monotonic by definition, and aligns timestamps to actual capture time (better for any future telemetry/replay tooling).

**C. Tune visibility thresholds per joint, not globally.** The single 0.5 gate is too liberal for noisy joints (wrists, ankles when partially occluded) and too strict for confidently visible torso joints. Recommended per-joint policy:
- Torso (shoulders/hips): use any value — they're rarely below 0.6 when in frame.
- Knees: ≥ 0.55 (tend to flicker behind the front leg in side-view squats).
- Ankles: ≥ 0.60 (often clipped or shoe-occluded).
- Wrists: ≥ 0.60.
- Elbows: ≥ 0.55.
- Synthetic neck/root: same gate as their components — already enforced.

**D. Pass camera orientation explicitly to `MPImage`.** Right now you set rotation/mirroring on the AV connection but feed the buffer into MPImage with no orientation hint. That works because the buffer is pre-rotated, but it leaves you no way to use the back camera or non-portrait orientation in future. Use `MPImage(sampleBuffer:orientation:)` with `.up` so the contract is explicit.

### 2.3 Smoothing — currently the single biggest visual quality win available

Right now there is **no smoothing on the rendered skeleton**. EMA with α=0.4 exists only on derived angles inside `UniversalRepCounter` (`UniversalRepCounter.swift:47–48`). The visible bones jitter every frame and the angle arcs strobe.

The right fix is the **One Euro Filter** (Casiez et al., CHI 2012) per landmark coordinate. It's a one-pole adaptive low-pass that gives low jitter at low speed and low lag at high speed — exactly what a fitness app needs. Reference impl: <https://gery.casiez.net/1euro/>.

Recommended implementation:
- One filter per `(JointName, axis)` — 33 × 3 = 99 filters total.
- `minCutoff = 1.0` Hz, `beta = 0.007`, `dCutoff = 1.0` Hz as starting parameters; tune empirically.
- Apply *before* angles are computed and *before* the canvas draws.
- For derived angles, additionally apply a small EMA (α≈0.6) on top — the angle is a non-linear function of coordinates, so smoothing both layers reduces visible flicker without adding meaningful lag.

This single change will make Spotter feel ~2× more polished without touching anything else. Most pose-based fitness apps that look "production grade" use One Euro under the hood (Google's own MediaPipe Holistic exposes an optional smoothing landmarks calculator that wraps One Euro internally).

### 2.4 What MediaPipe cannot do (and how to design around it)

These are real, documented limits — own them in product, don't try to engineer around them.

| Limitation | Implication for Spotter |
|---|---|
| **No spinal landmarks** between shoulder midpoint and hip midpoint. | You cannot reliably detect lumbar rounding (the #1 deadlift cue). Best you can do is shoulder-to-hip vector orientation, which conflates lumbar + thoracic + pelvic tilt. Ship the deadlift with a softer spine cue and rely on side-view cues for "back rounding" rather than promising injury detection. |
| **Wrist orientation (pronation/supination) unobservable.** | You cannot tell hammer curls from regular curls from grip pattern alone. The current `hammerCurl` exercise uses identical landmarks as `bicepCurl`. Either drop hammer-curl-specific feedback or use a hand-gesture/wrist-orientation classifier on top. |
| **Side-view occlusion of far limb.** | Side-view squats hide the back leg; side-view push-ups hide the far shoulder. Your `.bestAvailable` selector picks one side only — that's correct, but you also need to **detect which side is camera-facing** and prefer that one rather than always picking right. |
| **Z-coordinate is regressed, not measured.** | Don't promise "3D form analysis." 3D world landmarks are only reliable for relative motion (same person, same setup). Avoid absolute claims like "your knees are 4cm forward of your toes." |
| **Clothing/shoes degrade ankle precision.** | Heel-rise check (`squat_heel`, threshold 0.02 = ~2% of frame height) is right at the noise floor on a side view. False positives are likely with athletic shoes. Bump threshold to 0.025–0.03 and require the violation to persist for ≥3 frames before firing. |
| **Knee FPPA is 2D-projection, not true valgus.** | Published clinical research shows 2D FPPA captures only 23–30% of variance of true 3D knee abduction. That's still useful — Reliability is "good-to-excellent" for screening — but don't claim "injury risk detection." Frame as "knee position cue." |

### 2.5 Reported MediaPipe accuracy for fitness use (literature anchor)

Approximate, multi-study consensus for sagittal-plane joint angles vs Vicon (treat as ranges, not specs):

- **Knee flexion in cyclical exercises:** RMSE ≈ 5–10°, ICC ≈ 0.85–0.95 within-subject. ([Knee flexion/extension validation](https://www.researchgate.net/publication/369058814_Knee_FlexionExtension_Angle_Measurement_for_Gait_Analysis_Using_Machine_Learning_Solution_MediaPipe_Pose_and_Its_Comparison_with_Kinovea_R), [3D Pose Stereo accuracy study](https://pmc.ncbi.nlm.nih.gov/articles/PMC11644880/))
- **Hip flexion:** similar to knee, often slightly worse due to hip-belt occlusion.
- **Frontal-plane (knee valgus):** RMSE ≈ 8–15°, much noisier. ([FPPA validity comparison](https://pmc.ncbi.nlm.nih.gov/articles/PMC9718689/))
- **Inter-rater reliability of clinically-graded squat depth from 2D video:** ~5–8° — **MediaPipe is in the same ballpark as a single human rater**, which is the right way to frame the product to users.

---

## 3 · Skeleton Overlay (`TrainerOverlayView.swift`)

### What it does well
- Pure SwiftUI `Canvas` — no GPU dance, no UIKit conversion friction.
- Confidence-gated drawing (only joints in the dictionary, which already implies visibility ≥ 0.5).
- Per-joint violation color flip (red for current form-rule violation) — clean visual feedback signal.
- Angle arc + label rendering with shortest-path arc normalization.

### What it's missing
1. **No smoothing** (covered in 2.3).
2. **No spine connection.** `JointName.bonePairs` includes torso edges (left shoulder ↔ right shoulder, hip ↔ hip, shoulder ↔ hip on each side) but nothing connecting `neck` to `root`. Adding the spine line dramatically improves visual readability of body line.
3. **No mirror-aware labeling.** When the overlay paints "Knee" angle on the camera-mirrored image, the label sits on what the *user* sees as their left, but the underlying joint is MediaPipe-labeled `right`. If you ever localize coaching ("your right knee is caving"), you must remap.
4. **Arc radius is hardcoded `22`** in pixels. On larger phones (Pro Max), arcs feel small; on smaller phones, labels overlap. Make `arcRadius` a function of the angle joint's screen-space distance to its parent (e.g. `0.25 * boneLength`).
5. **No motion trails.** A 6-frame fading trail on the wrist for curls or the hip for squats is a tiny addition that massively improves perceived quality.
6. **No depth shading.** Bones could be slightly thinner / dimmer when their `z` is far from the camera. Cheap polish.

---

## 4 · Angle Calculation (`AngleCalculator.swift`) — three real bugs

### 4.1 BUG: `hip_center` and `shoulder_center` are silently mis-resolved
At lines 218–221:
```swift
case "hip_center":      return side == "left" ? "leftHip" : "rightHip"
case "shoulder_center": return side == "left" ? "leftShoulder" : "rightShoulder"
```

These names imply the midpoint, but the function returns *one side*. The synthetic `.root` and `.neck` midpoints already exist (`PoseEstimator.swift:176–195`). Resolve `hip_center` → `.root` and `shoulder_center` → `.neck`.

**Affected exercises:** `hipAbductionStanding` (uses `ankle_left`, `hip_center`, `ankle_right` to compute leg-spread angle — currently anchored on one side, biases the angle); `jumpingJacks` (same, leg-spread angle); `warrior` (uses `wrist_left`, `shoulder_center`, `wrist_right` for arm line).

This is the highest-priority correctness bug in the codebase.

### 4.2 BUG: `bodyLineAngle` and hip-flexion angle are duplicates
At `computeAllAngles` lines 94–107, the right-side body-line key and right-side hip-flexion key have identical triples (shoulder→hip→ankle). Two storage keys, one math. Either delete the duplicate or fix `bodyLineAngle` to be the actual body-line metric (e.g., the angle between the floor and the shoulder-to-ankle vector — a much better push-up/plank cue).

Recommended fix — make `bodyLineAngle` actually be **deviation from a straight line**:
```swift
// Compute angle between (shoulder→hip) and (hip→ankle) vectors.
// 180° = perfectly straight body line. <180° = sag (hips low).
// >180° = pike (hips high).
```
That is what the current keying *means* — but the function returns the standard 3-point flexion angle, which folds at 180° (`AngleCalculator.swift:127–131`). To get a signed deviation, drop the fold and instead compute `signed_angle - 180°`.

### 4.3 BUG: Right-side bias in `.bestAvailable`
Lines 174–177 always prefer right shoulder/hip/knee/ankle over left. For a unilateral exercise like a forward lunge, the user could be lunging with either leg — you want the *forward* leg, not the right. The fix is one of:
- **Detect which side is more bent** (smaller knee angle = more flexion = forward leg) and pick that.
- **Detect which side has higher visibility scores** and pick that.
- For side-view exercises, **pick the camera-near side** (whichever side has higher z-confidence after orientation analysis).

A simple heuristic that solves most cases:
```swift
case .bestAvailable:
    // Prefer the side with greater knee flexion (smaller angle), if both visible.
    if let l = leftAngle, let r = rightAngle { return min(l, r) }
    return leftAngle ?? rightAngle
```
For exercises where you want the *less* bent side (e.g. trailing leg in side lunge), expose this as a `MeasurementSide.minOrMax` choice on `AngleDefinition`.

### 4.4 Other issues

- **2D-only positional checks.** Even when 3D world joints are available, `evaluateSingleCheck` uses 2D coordinates. Knee valgus, in particular, is more accurately computed in 3D (project to the user's frontal plane using the shoulder-line normal) — but this requires confident world coordinates.
- **No angle confidence.** An angle's quality depends on the visibility of all three involved joints. Currently you trust any returned angle equally. Compute and surface `min(visA, visB, visC)` as a confidence value alongside each angle, so downstream code can decline to fire form rules when confidence is low.
- **Hard-coded knee-valgus sign convention** (`AngleCalculator.swift:475–476`) — works only because the camera is mirrored at the AV connection. Document the assumption in the function header. If anyone ever turns off mirroring to support back-camera mode, the sign flips silently.

---

## 5 · Rep Counter (`UniversalRepCounter.swift`) — the heart of the engine

### 5.1 What's good

- One state machine for every rep-based exercise. `idle → down → up → idle`.
- Two-frame hysteresis on phase transitions (`hysteresisFrameCount = 2`) blocks single-frame noise from triggering reps.
- `minRepDuration` (per-exercise, default 0.5s) blocks bouncing.
- Per-rep extreme-angle tracking (deepest point of the down phase) drives quality scoring.
- EMA on angles (α=0.4) damps frame-to-frame jitter.

### 5.2 What's missing

- **Velocity / tempo signals.** You compute `repDurations` but only deduct points when tempo is out of `tempoRange`. There's no per-rep mean velocity, no concentric vs eccentric duration, no "explosive concentric" bonus, no "controlled eccentric" cue. These are the things experienced lifters care about. Adding `concentricMs`, `eccentricMs`, and `peakAngularVelocity` per rep is a 50-line addition with significant coaching upside.
- **Asymmetry tracking.** `FormFeedbackEngine.checkBilateralAsymmetry` runs only as a fallback when no other feedback fires. For unilateral movements (lunges, single-leg deadlifts, hip abduction), asymmetry should be a first-class metric, not a fallback.
- **Range-of-motion drift.** Over a 12-rep set, depth often degrades. You have the data (`extremeAnglesDuringDown` per rep) but never compute "ROM drift across the set" or coach on it. Best-in-class apps do.
- **No per-rep telemetry export.** `extremeAnglesDuringDown` and `repDurations` reset on `reset()` and never get persisted. Adding a `RepRecord` struct that captures `{repIndex, peakAngles[String:Double], duration, formScore, violations}` and accumulating into the workout session is the foundation for all future analytics.
- **Form score is opaque.** Users see a number with no breakdown. Surface "ROM: -8, tempo: -5, cues: -10" so the score is debuggable.
- **No "false rep" detection.** A user can game the rep counter by half-cycling through the threshold pair. You want a *quality gate* that doesn't count reps with form score below 50 (or counts them as "partial").

### 5.3 The dead-code problem: `SquatRepCounter.swift`

This file is 200+ lines of legacy logic that:
- Hardcodes thresholds (120/150) that *disagree* with `ExerciseLibrary.squats` (100/160).
- Has no EMA.
- Has a labeling bug at lines 85–88 that will fall back to *hip angle* when the knee triple isn't visible — and store it under the `kneeAngle` key. Anyone debugging this will go insane.
- Is not referenced anywhere in `TrainerSessionView.swift` (which uses `UniversalRepCounter` exclusively at line 85).

Delete it, or move it to `Legacy/` with a `@available(*, deprecated)` warning.

---

## 6 · Form Feedback Engine — strong skeleton, weak cues

### 6.1 The cascade is correctly ordered

`FormFeedbackEngine.evaluate` runs in this priority order, short-circuiting on the first hit:
1. Body missing / partial (very loose threshold — see issue below).
2. Frame position (segmentation-mask centering).
3. Joint visibility (required-joints list).
4. Form rules (angle thresholds gated by phase).
5. Positional checks (only if step 4 produced nothing).
6. Bilateral asymmetry (last resort).

This is the right cascade. Missing-body trumps in-frame coaching. Visibility trumps form. Form trumps the 15° symmetry nudge.

### 6.2 Issues

**A. `joints.count < 4` is a bad heuristic** (`FormFeedbackEngine.swift:129–136`). MediaPipe almost always returns 30+ landmarks when a person is in frame. A real `< 4` happens only at the moment of detection or full-body exit. Replace with: "if `requiredJoints` for this exercise has more than 50% missing → body_partial."

**B. Cooldowns are uniform.** Critical cues (knee valgus during a heavy squat) probably want a 4-second cooldown, not 8. Info-severity cues probably want 12+. The library has `cooldownSeconds` per rule already — but most are set to 8 or 10 by default. Tune severity-driven defaults and override per-rule when needed.

**C. No "cue staircase."** The same cue fires the same way every time. Best-in-class coaching gradually escalates: gentle nudge → direct → blunt → "let's pause and reset." You have two personalities (`good` / `drill`) but no escalation curve.

**D. No "encouragement" channel.** When the user nails a rep, nothing fires. Form rules only ever produce negative feedback. Add a positive-feedback path tied to rep events with form score > 90: "Perfect rep, that's the depth."

**E. Bilateral asymmetry is single-threshold.** `bilateralAsymmetryThreshold = 15.0` is treated as a hard cutoff. In real biomechanics, 5–10% asymmetry is normal; 15% sustained over multiple reps is concerning; 20%+ is a coaching event. Move to a smoothed running average and only fire after 3 consecutive asymmetric reps.

### 6.3 Voice — the entire personality system has no voice

`VoiceCoachManager.swift` is a 30-line stub. Every method (`prefetchRepCounts`, `playRep`, `playMotivation`) is `// no-op`. Yet the entire library is written in two voice personalities (`feedbackGood` / `feedbackDrill`) and `MotivationEngine` calls `playMotivation` (which does nothing).

This is the single largest user-experience gap in the product. Without voice, "drill sergeant mode" is just text on a screen.

Recommended path (in order of cost):
1. **Cheap baseline:** `AVSpeechSynthesizer` with two voice profiles (calm / aggressive). Ships in 1 day. Solves the gap.
2. **Better:** ElevenLabs streaming with two pre-cloned voice IDs (one "supportive coach", one "drill sergeant"). Cache by phrase hash. ~2-3 days.
3. **Best:** ElevenLabs WebSocket streaming with sub-200ms first-byte latency, plus a small set of pre-rendered short cues ("rep 1", "rep 2", …, "thirty"). The pre-renders cover the rep-count chant; the streaming covers form cues.

Either way, add a `cueQueue` with priority + ducking — never let the rep-count chant talk over a critical form cue.

---

## 7 · Per-Exercise Biomechanics Audit

I'll go exercise by exercise. For each I'll give: (1) what it tracks, (2) what's right, (3) what's wrong / missing, (4) what's reasonable to ship.

### 7.1 Squats (id: `squat`, lower body, front)

**Tracks:** `kneeAngle` (both sides averaged), `hipAngle` (best-available).
**Thresholds:** down enters at knee < 100°, up enters at knee > 160°. Quality target = 90°.
**Form rules:** depth (knee max 90°), hip angle for back straight (min 65°).
**Positional checks:** knee valgus (threshold 0.15), heel rise (0.02).

**What's right:**
- Front view is the right camera position for valgus detection.
- Quality target of 90° corresponds to "thighs parallel to floor", which is the classic NSCA squat depth definition.
- Both-side averaging on knee angle is appropriate for a bilateral movement.

**What's wrong / missing:**
- **No torso lean check via shoulder-to-hip vertical.** "Back straight" is being approximated by `hipAngle` (shoulder→hip→knee). That conflates trunk lean with hip flexion — at 90° depth, you *want* about 45° trunk lean. The current `minAngle: 65` rule will fire on perfectly good high-bar squats and miss real Good-Morning tendencies.
- **No knees-over-toes check.** Knee anterior translation past the toe is debated but commonly flagged. Compute `knee.x - ankle.x` in 3D and surface as info-level cue, not warning.
- **No depth descent rate (eccentric speed).** Bouncing out of the bottom is a coaching event.
- **No bar-path metric.** Even bodyweight, the hip vertical trajectory should be ~vertical with slight forward shift. You can compute `(hip.x_top - hip.x_bottom)` and flag if hips shoot back too far.
- **Heel rise threshold (0.02) is on the noise floor for shoes.** Recommend 0.025 + 3-frame persistence.
- **The `qualityTarget: 90` is correct, but `qualityTargetIsMinimum: false` is misleadingly named.** With "false", the user *must go below* the target. Rename to `qualityTargetIsCeiling` for clarity.

**Per-exercise recommendation:**
Add a third angle: `trunkAngle = angle between vertical and shoulder→hip vector`. Add a positional check `kneeOverToe` (info severity). Tune valgus threshold to 0.12 (slightly stricter — current 0.15 misses real valgus on women athletes who are exactly the highest-risk demographic).

[Squat depth & knee biomechanics evidence](https://pmc.ncbi.nlm.nih.gov/articles/PMC11618833/), [NSCA squat depth article](https://www.nsca.com/education/articles/nsca-coach/considerations-for-squat-depth/), [FPPA validity for screening](https://pubmed.ncbi.nlm.nih.gov/22104115/).

### 7.2 Sumo Squats (id: `sumoSquat`)

Mirrors `squats` with depth target 85° (slightly deeper, anatomically appropriate for wider stance). Looks correct. Same recommendations as 7.1 apply.

### 7.3 Lunges (id: `lunge`, side view)

**Tracks:** `frontKneeAngle` (`.bestAvailable`), `hipAngle`.
**What's wrong:** **`.bestAvailable` is the right-side bias bug**. If the user lunges with the left leg forward, the engine measures the right (back) leg as "front knee." Fix the right-side bias as in 4.3 *or* add a heuristic that picks the more-flexed leg as the front leg.

Also: no back-knee tracking. Classic lunge cue is "back knee almost touches ground" — you have the joint, just compute its `y` coordinate at peak depth and surface as a depth proxy.

### 7.4 Side Lunges (id: `sideLunge`)

**What's wrong:** `kneeAngle` (the working knee) uses `.bestAvailable` — same right-side bias. `trailingKneeAngle` uses `.both` (averages both knees) — but you only want the *trailing* knee, which is the straight leg. The averaging will silently dilute the rule.

**Fix:** Pick the more-flexed leg as `kneeAngle`, the straighter leg as `trailingKneeAngle`. Add the `MeasurementSide.minOrMax` enum (4.3).

### 7.5 Glute Bridge (id: `gluteBridge`, side view)

**Tracks:** `hipAngle` (shoulder→hip→knee).
**Thresholds:** down enters at hip > 160°, up enters at hip < 130°. Quality target = 170° (minimum). Down-when-up direction (lockout = "down" phase).

**Wait** — read carefully: `downThreshold: enterAbove: 160` and `upThreshold: enterBelow: 130`. So the "down" phase is *up at the top* (lockout) and the "up" phase is *down at the bottom*. This works because of the `downIsDecreasing` flag in `UniversalRepCounter` (line 74), but the naming is *deeply* confusing. The `down`/`up` phase names made sense for squats; for hinges they're inverted.

**Recommendation:** Rename `RepPhase.down` → `RepPhase.peak` and `up` → `RepPhase.trough`. "Peak" is whichever extreme the rep targets. Or introduce a per-exercise direction enum (`.contractionAtBottom` / `.contractionAtTop`) so phase names are exercise-relative.

**What's missing:** No glute squeeze hold check (good glute bridges have a 1-second hold at the top). Add a "hold time at peak" requirement when `qualityTargetIsMinimum: true`.

### 7.6 Hip Abduction Standing (id: `hipAbduction`)

**Tracks:** `legAbductionAngle` using `ankle_left`, `hip_center`, `ankle_right`.
**Bug:** `hip_center` resolves to one side (4.1), so the angle is anchored at *one* hip joint, not the midpoint. The actual angle measured isn't the leg spread — it's the angle from one ankle, through one hip, to the other ankle. Geometrically still informative but biomechanically wrong-shaped.

**Fix:** Resolve `hip_center` → `.root` (synthetic midpoint).

**Also:** With both legs treated symmetrically, the engine can't tell which leg is being lifted. For a unilateral exercise this is a problem. Need per-leg tracking (compute `leftLegLift = leftHip→leftAnkle vector vs vertical` and `rightLegLift = ...`, then take the larger).

### 7.7 Leg Raises (id: `legRaise`, side view)

**Tracks:** `hipFlexionAngle` (shoulder→hip→ankle), `kneeAngle`.

Note: with the user lying on their back, the side view sees the body horizontally. `hipFlexionAngle` measured here is the angle from shoulder, through hip, to ankle — at rest (legs straight on ground) this is ~180°; at peak (legs vertical) this is ~90°. Quality target = 95°. That's right.

**What's missing:**
- **No anti-lift check on lower back.** The classic leg-raise cue is "press your low back into the floor". You can't measure this from a single side-view camera with no depth — but you *can* approximate by tracking shoulder.y vs hip.y. If shoulder rises noticeably during a rep, the user is using lats to compensate.
- **No leg-drop control check.** Velocity at the eccentric should be < some threshold. You have the data.

### 7.8 Wall Sit (id: `wallSit`, side view, isometric)

Decent. Tracks knee angle (target 90°) and hip angle (back flat). Missing: **time-under-tension scoring**. An isometric exercise's only quality dimension is "did you hold the right position for the right time." Right now there's no surfacing of a hold timer in the library spec; that's UI-level.

**Recommendation:** Add `targetHoldDuration: TimeInterval?` to `ExerciseDefinition` (today only `isometric` movement type sets the *expectation* but not the duration). Then `UniversalRepCounter.processIsometric` should compare cumulative-in-position-time vs target.

### 7.9 Deadlift (id: `deadlift`, side view)

**Tracks:** `hipAngle` (shoulder→hip→knee), `kneeAngle`.
**Thresholds:** down enters at hip < 100°, up enters at hip > 165°. Quality target = 90°.
**Form rules:** back rounding (`hipAngle ≥ 70°` during down), lockout (`hipAngle ≥ 170°` during up), knees-stay-soft (`kneeAngle ≥ 140°` during down).

**The hard truth:** **You cannot detect lumbar rounding from MediaPipe alone.** There are no spinal landmarks. The `hipAngle` rule is using shoulder-to-hip-to-knee as a proxy, but a user can round their thoracic spine while keeping shoulder-hip-knee at exactly the same angle. This is a **safety claim you cannot honor.**

**Two options:**
1. Drop the deadlift from the library until you have a spine signal (or until you ship Apple Vision 3D + LiDAR fusion).
2. Reframe the cue as "Keep your hips back" or "Maintain your hinge angle" — *which is actually what `hipAngle ≥ 70°` measures* — and stop claiming back-rounding detection.

I recommend option 2. The deadlift is too important to drop. Update the cue copy to remove "rounding like a scared cat" and instead coach hip hinge depth and lockout.

**Other issues:**
- `kneeAngle ≥ 140` for "knees soft" is right, but reps where the user does a stiff-leg RDL will have `kneeAngle ≈ 170°+` constantly, which by your rule is *fine* — except your `targetMuscles` advertise hamstrings + glutes, which is RDL territory, not conventional deadlift. Either split into two exercises (`conventionalDeadlift` vs `romanianDeadlift`) or make the knee angle range explicit.
- No bar path tracking (you can use the wrist as a proxy — wrist.x should travel near vertical).

### 7.10 Calf Raises (id: `calfRaise`, side view)

**Tracks:** `kneeAngle` only (used to detect that the *knee stays straight*).

**The fundamental problem:** Calf raises are mostly an **ankle plantarflexion** movement. MediaPipe gives you ankle, heel, and foot-index landmarks; you can compute ankle plantarflexion as the angle between (knee→ankle) and (ankle→foot_index). The current implementation uses knee angle as the rep-counting primary, which doesn't actually correlate with plantarflexion.

**Fix:** Add `ankleAngle = angle(knee, ankle, foot_index)`. Make it the `primaryAngleKey`. Quality target ~110° (full plantarflexion = ankle, foot stretched out, foot points down). Knee-straight remains as a form rule.

### 7.11 Bicep Curls (id: `bicepCurl`, front)

**Tracks:** `elbowAngle` (both sides), `shoulderAngle`.
**Quality target:** 40° (full elbow flexion at top).

**What's right:** Both-side averaging. Anti-swing rule (`shoulderAngle ≤ 30°` — the elbow shouldn't drift forward).

**What's missing:**
- No torso lean check. Cheating curl = leaning back at the rep top. Compute trunk angle (shoulder→hip vs vertical) and require it stay within 10° of upright.
- No tempo check beyond `tempoRange`. Good curls have a 1–2s eccentric, a brief pause at top, and a 1–2s concentric. Surface concentric/eccentric times separately.
- The `qualityTarget: 40` is the elbow angle at peak contraction. Anatomically, full bicep curl flexion is ≈ 30–40° (you can't go to 0° because the upper arm and forearm hit each other). 40° is reasonable.

### 7.12 Hammer Curls (id: `hammerCurl`)

Identical landmarks to bicep curls. **MediaPipe cannot distinguish hammer (neutral grip) from supinated curls** — there's no reliable wrist-rotation landmark. Same form rules will apply. Either remove this exercise or run a hand-orientation classifier on top.

### 7.13 Push Ups (id: `pushup`)

**Tracks:** `elbowAngle`, `shoulderAngle`, `bodyLineAngle`.

**Camera position is `front` but `setupInstruction` says "side view for more accuracy."** This is the right hedge — front is the easy-to-get-into setup, side view is more measurable. Consider supporting both with different rule sets.

**Issues with the body-line rules:**
- `pushup_bodyline` has `minAngle: 160, maxAngle: 180`.
- `pushup_hips_sag` has `minAngle: 155` (hips dropping = critical).
- `pushup_hips_pike` has `maxAngle: 185` (hips piking = warning).

These three rules **overlap in their valid ranges**. If `bodyLineAngle = 162`, `pushup_bodyline` is fine (160 ≤ 162 ≤ 180), `pushup_hips_sag` is fine (155 ≤ 162), and `pushup_hips_pike` is fine (162 ≤ 185). But at 184, `pushup_bodyline` *fires* (max 180 exceeded), `pushup_hips_pike` is fine (max 185 not exceeded), and the user gets the wrong cue first.

The `bodyLineAngle` math itself folds at 180° (`AngleCalculator.swift:127–131`), so it can never *exceed* 180°. The `maxAngle: 180` and `maxAngle: 185` clauses are inert. The pike check **never fires.** This is a real bug.

**Fix:** Recompute `bodyLineAngle` as a *signed* deviation from straight (positive = pike, negative = sag). Then the rules become:
- Critical sag: `bodyLineAngle < -15°`
- Warning pike: `bodyLineAngle > +15°`
- Acceptable: ±10°.

[Push-up biomechanics & 90° elbow flexion validation](https://efsupit.ro/images/stories/nr%201%202012/vol%2012_1_%20art%2012.pdf), [push-up vGRF and elbow angle research](https://pmc.ncbi.nlm.nih.gov/articles/PMC4327800/).

### 7.14 Lateral Raises (id: `lateralRaise`, front)

Solid spec. The `latrise_shrug` positional check uses `shoulderLevel` (compares left vs right shoulder y) which is *not* a shrug detector — a shrug is *both* shoulders elevating. To detect shrugs you need to track shoulder.y over time relative to neck.y baseline.

**Fix:** Compute `shoulderHeight = avg(leftShoulder.y, rightShoulder.y)`, baseline at exercise start, flag if it rises by > 3% during the rep. Add this as a new `CheckType.shoulderShrug`.

[Scapulohumeral rhythm & overhead pressing biomechanics](https://www.synergystrength.ca/blog/2025/4/7/scapulohumeral-rhythm-understanding-shoulder-mechanics-under-load), [glenohumeral & scapular biomechanics](https://www.jospt.org/doi/10.2519/jospt.2009.2835).

### 7.15 Front Raises (id: `frontRaise`, side view)

`frontrise_sway` uses `hipAngle` defined as `knee→hip→shoulder`. That's an unusual orientation. At standing rest, this is ~180°. Lean back = angle decreases? Or increases? Without checking against the live data this is hard to pin down. **Verify the sign convention at runtime and document it inline.**

### 7.16 Overhead Dumbbell Press (id: `overheadPress`, front)

Similar to shoulder press. Front view will struggle with the *path* (you can't see if the user is pressing in front of vs behind the head). Side view would tell you scapular plane orientation. Recommend dual-view support.

### 7.17 Cobra Wings (id: `cobraWings`)

A scapular retraction exercise. The angle `shoulderAngle` (hip→shoulder→elbow) won't change much during scapular retraction without arm motion. The actual movement is **scapular adduction** (shoulder blades pinching together) which happens *behind the chest cavity* — invisible to MediaPipe.

**This exercise is not measurable from MediaPipe.** What you *can* measure is whether the elbows are at 90° throughout. Either reframe the exercise to a posterior-deltoid raise (where elbows actually move backward) or drop it.

### 7.18 Overarm Reach Bilateral (id: `overarmReach`)

Reasonable. Same notes as front raises (shoulder flexion).

### 7.19 Jumping Jacks (id: `jumpingJack`)

**Tracks:** `armRaiseAngle` and `legSpreadAngle`. The latter uses `hip_center` — same midpoint bug (4.1).

**Missing:** No timing check. Jumping jacks should be cyclic with consistent rhythm; degraded rhythm is a fatigue signal. Add a "rhythm consistency" metric: standard deviation of `repDuration` across a 10-rep window.

### 7.20 Knee Raises Bilateral (id: `kneeRaise`)

`hipFlexionAngle` is `.bestAvailable` — picks one side. For a bilateral alternating exercise this means the engine only "sees" one knee. If the user alternates legs, the rep counter will count every other rep (when the tracked side moves) and miss the other side entirely.

**Fix:** Track both `leftHipFlexionAngle` and `rightHipFlexionAngle` separately. Count a rep when either side's angle drops below threshold. (Same fix needed for `highKnees`, `mountainClimber`.)

### 7.21 Sit Ups (id: `sitUp`, side view)

Tracks `torsoAngle = shoulder→hip→knee`. Down threshold = 90°, up threshold = 140°. Quality target = 70°. Reasonable.

**Missing:** No neck-pull check (very common cue — user pulls on neck with hands, shoulders shrug forward). The face landmarker could detect head pitch — currently unused. Add a head-forward-of-shoulders check.

### 7.22 V-Ups (id: `vUp`, side view)

Tracks torso angle, hip flexion, knee. `vup_legs_straight` requires knee ≥ 160° during the entire movement — fair.

**Missing:** No "hands-touch-toes" proximity check. You have all 4 endpoints (wrists, ankles); compute Euclidean distance and surface as the depth metric.

### 7.23 Plank (id: `plank`, side view, isometric)

Body-line angle range issue same as pushup (7.13).

**Missing:** Hold timer, fatigue ramp (body line typically degrades after 30s), shoulder-stack check (shoulders should be over wrists/elbows).

### 7.24 High Knees (id: `highKnees`)

Same `.bestAvailable` issue as knee raises (7.20). Also: `tempoRange: 0.3...1.5` and `minRepDuration: 0.2` — at 0.3s/rep that's 200 reps/min which is faster than humanly possible. Tighten.

### 7.25 Mountain Climber (id: `mountainClimber`, side view)

Side view + `.bestAvailable` means you only see one knee. For an alternating exercise this is a problem (same as 7.20). Also, mountain climbers are often coached front-view to check hip alignment.

### 7.26 Downward Dog (id: `downwardDog`, isometric, side view)

The `dd_hips` rule uses `hipAngle` and gates the *whole* exercise — but `hipAngle` is shoulder→hip→ankle here, which at full down-dog is ~70° (hips high, body in inverted V). So `maxAngle: 90` is the rule — angle should be *below* 90° (small angle = hips high). This is correct but the variable naming is confusing because "hipAngle" usually implies hip flexion.

OK as-is. Could add an arm-line straight check.

### 7.27 Warrior II (id: `warrior`, isometric, front)

`armLineAngle` uses `wrist_left, shoulder_center, wrist_right` — `shoulder_center` mid-point bug (4.1). The arm-line angle should be ~180° when arms are straight out to the sides. Currently it's anchored at one shoulder, not the midpoint, so the angle reads ~135° even with perfect form.

**Fix:** Resolve `shoulder_center` → `.neck`.

### 7.28–7.30 Yoga gap

The library has only `downwardDog` and `warrior`. The yoga category advertises "Flexibility & balance" but ships nothing else. At minimum: tree pose, chair pose, cobra, plank-to-up-dog, mountain pose, warrior I, warrior III, triangle. Many of these are isometric and pose-classifiable from MediaPipe.

---

## 8 · Cross-cutting issues recap

1. **`hip_center` / `shoulder_center` mis-resolution** (4.1) — affects 4 exercises.
2. **`bodyLineAngle` duplicate / fold-at-180 bug** (4.2, 7.13) — pushup pike never fires.
3. **`.bestAvailable` right-side bias** (4.3) — affects every unilateral or alternating exercise.
4. **`SquatRepCounter.swift` is dead code with bugs** (5.3) — delete.
5. **`VoiceCoachManager` is a no-op stub** (6.3) — kills the personality system.
6. **CPU-only inference, no smoothing on landmarks** (2.1, 2.3) — biggest perf+polish win.
7. **No per-rep telemetry persistence** (5.2) — kills future analytics.
8. **Camera mirroring not reflected in landmark labels** (2.4) — coaching that names sides will be backward.
9. **Rep-phase naming is squat-centric** (`down` ≠ "the contracted position" for hinges) — confusing.
10. **Cooldowns and severities are uniform** — ignore severity gradients in real coaching.

---

## 9 · What the engine can't do today (capability gaps)

- **No tempo decomposition.** Concentric vs eccentric duration not exposed.
- **No bar/limb path tracking.** Wrist trajectory for curls, hip trajectory for squats — uncomputed.
- **No fatigue progression metric.** ROM degradation, tempo decay, asymmetry growth across a set — uncomputed.
- **No exercise classification (vs detection).** The user has to pick the exercise from the menu. There's no model that *recognizes* what they're doing. Best-in-class apps (e.g. Tempo) infer the exercise.
- **No rest-time coaching.** No detection of when a set ends and rest begins.
- **No range-of-motion personalization.** Every user has the same depth target. Should scale to height/limb-length.
- **No injury-history awareness.** Can't soften depth requirements for someone who flagged a knee issue at signup.
- **No equipment detection.** Dumbbell vs bodyweight, bar height, stability ball — none detected.
- **No multi-person handling.** `numPoses=1`. Drops gracefully but never coaches a partner workout.
- **No Apple Vision 3D fallback.** On LiDAR-equipped iPhones, [Apple's `VNDetectHumanBodyPose3DRequest`](https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest) gives true 3D in meters. Hybrid pipeline available but unimplemented.

---

## 10 · Recommended new exercises (drop-in specs)

The below are biomechanics-tractable from MediaPipe alone (no equipment-detection required). For each I'll give the angle keys, thresholds, primary rule, and rationale. These are ready to paste into `ExerciseLibrary.swift`.

### 10.1 Romanian Deadlift (RDL)
- **Why:** Distinct from conventional deadlift; hip-hinge with stiff knees. Highly trainable, hugely popular.
- **Camera:** side.
- **Angles:** `hipAngle` (shoulder→hip→knee), `kneeAngle`.
- **Thresholds:** down enters at hip < 110°, up enters at hip > 170°. Quality target 95° (less depth than conventional — RDL stops at hamstring tension).
- **Form rules:** keep `kneeAngle ≥ 155` throughout (RDL = stiff legs); lockout `hipAngle ≥ 170` at top.
- **Distinct from your current `deadlift`** which has knee soften ≥ 140 (more knee bend → conventional).

### 10.2 Hip Thrust (Bodyweight Bridge → Loaded)
- **Why:** Highest glute activation of any common exercise (StrengthLog, EMG studies cited in [glute activation comparison](https://www.strengthlog.com/romanian-deadlift-vs-squat-vs-hip-thrust-comparison-of-muscle-activity/)).
- **Camera:** side.
- **Angles:** `hipAngle` (shoulder→hip→knee), `kneeAngle`.
- **Thresholds:** down enters at hip > 160° (lockout = "down" phase, top of bridge), up enters at hip < 100° (bottom).
- **Form rules:** lockout extension `hipAngle ≥ 175°` at top; knee bend `kneeAngle ∈ [80°, 110°]` (90° at bench).
- **Note:** This *is* an evolution of your existing `gluteBridge` — distinguish bench-elevated thrust from floor bridge in copy/setup.

### 10.3 Bulgarian Split Squat
- **Why:** [Hip-dominant unilateral lift, 70-85% of force through front leg](https://pmc.ncbi.nlm.nih.gov/articles/PMC8136570/). Great test of knee stability.
- **Camera:** side.
- **Angles:** `frontKneeAngle` (the more flexed leg), `trunkAngle`.
- **Thresholds:** front knee down < 100°, up > 155°. Quality target 90°.
- **Form rules:** trunk lean ≤ 30° from vertical; back-knee almost touches floor (depth proxy).

### 10.4 Reverse Lunge
- **Why:** Lower joint stress than forward lunge ([Bulgarian split squat alternatives](https://thedbmethod.com/blogs/beyond-the-squat/7-bulgarian-split-squat-alternatives)). Needs front-leg knee tracking.
- **Camera:** side.
- **Spec:** Same as `lunge` but movement direction reversed; thresholds identical. Mostly a copy with new id and copy text.

### 10.5 Step-Up
- **Why:** Functional unilateral lift. Tractable — just needs a front-knee-up cue.
- **Camera:** side.
- **Angles:** `frontKneeAngle`, `hipAngle`.
- **Thresholds:** down (foot on box) `frontKneeAngle < 100°`, up `frontKneeAngle > 165°`.
- **Form rules:** drive through heel (heel-rise check on stepping foot).

### 10.6 Bird Dog (Anti-rotation core)
- **Why:** Most-prescribed core stability exercise (UC Davis fundamental core sheet, [bird dog overview](https://www.onepeloton.com/blog/bird-dog-exercise)). Tractable — opposite arm/leg extension.
- **Camera:** side.
- **Movement type:** `repetition` (one rep = one extension).
- **Angles:** `oppositeArmExtension` (hip→shoulder→wrist on extending side), `oppositeLegExtension` (shoulder→hip→ankle on extending side).
- **Form rules:** body line straight (`bodyLineAngle ≈ 180°` throughout); ipsilateral pair (left arm + right leg, or vice versa).

### 10.7 Dead Bug
- **Why:** Same family as bird dog. ([Strong core exercises overview](https://www.jefit.com/wp/exercise-tips/strong-core-exercises-dead-bug-side-bridge-and-bird-dog/))
- **Camera:** side.
- **Movement type:** `repetition`.
- **Angles:** `armExtensionAngle`, `legExtensionAngle`.
- **Form rules:** low-back doesn't lift off floor (shoulder.y ≈ hip.y throughout); contralateral pattern.

### 10.8 Russian Twist
- **Why:** Very popular core/oblique exercise. Tractable — torso rotation visible from front.
- **Camera:** front.
- **Angles:** `torsoTwistAngle` (shoulder-line orientation vs hip-line orientation, projected).
- **Form rules:** maintain v-sit position (`hipFlexionAngle ≈ 90°`).
- **Caveat:** Twist amplitude is hard to measure without 3D. Treat as a count-only exercise and gate quality on staying in the v-sit pose.

### 10.9 Superman / Back Extension
- **Why:** Counter to all the abdominal work. Common in PT settings.
- **Camera:** side.
- **Angles:** `hipExtensionAngle`, `shoulderElevationAngle`.
- **Form rules:** lift both ends simultaneously; brief peak hold.

### 10.10 Single-leg RDL
- **Why:** Premier hamstring + balance exercise.
- **Camera:** side.
- **Angles:** `standingLegHipAngle`, `extendingLegToHipAngle`.
- **Form rules:** trailing leg in line with trunk (forms ~180° body-line); standing knee soft (155–170°).

### 10.11 Yoga additions (all front view, isometric)
- **Tree pose:** standing on one leg, opposite foot on inner thigh. Tractable: ankle position + standing leg straight.
- **Chair pose:** wall-sit-without-wall. Same angles as wall sit.
- **Triangle pose:** wide stance + side bend. Tractable: trunk-to-leg angle, opposite arm vertical.
- **Warrior I:** front knee 90°, back leg straight, arms overhead.
- **Mountain pose:** static standing alignment — tractable for posture feedback.

### 10.12 Push-up variants (each just a parameter tweak of pushup)
- **Diamond push-up:** narrower hand stance, deeper elbow flexion target.
- **Decline push-up:** body angle changed.
- **Knee push-up:** modified body line target (shorter lever).
- **Wide push-up:** elbows out more, less depth.

### 10.13 Quick wins by re-using existing logic
- **Reverse crunch:** mirror sit-up.
- **Bicycle crunch:** twist + alternating leg, count one rep per cycle.
- **Donkey kick:** mirror glute kickback (you'd need to add this exercise too).
- **Standing oblique crunch:** lateral trunk flexion, very tractable.

This adds **22+ new exercises** with minimal new infrastructure. The unblocking work is mostly: (a) fix the `hip_center` / `shoulder_center` resolution, (b) add `MeasurementSide.minOrMax`, (c) add `targetHoldDuration`, (d) add `bodyLineAngle` real signed-deviation math.

---

## 11 · The "best in the world" upgrade plan

Here's a prioritized roadmap. Each item is sized P0 (block-shipping fixes), P1 (significant quality win, 1–3 days), or P2 (multi-week investment).

### P0 — Correctness fixes (do these first, in this order)
1. Fix `hip_center` / `shoulder_center` resolution (4.1). 30-min fix.
2. Fix the `bodyLineAngle` duplicate + signed-deviation math (4.2). 2-hour fix.
3. Fix `.bestAvailable` right-side bias (4.3); add `MeasurementSide.minOrMax`. 4-hour fix.
4. Delete `SquatRepCounter.swift`. 5-min fix.
5. Replace `Date()` timestamps with `CMSampleBuffer` PTS in `PoseEstimator`. 15-min fix.
6. Add per-required-joint visibility threshold (vs flat 0.5). 2-hour fix.
7. Re-tune push-up body-line rules so the pike check actually fires (7.13). 1-hour fix.
8. Audit phase-naming: rename `down`/`up` to `peak`/`trough` or expose `contractionAtBottom`/`contractionAtTop` per exercise (5.5). 4-hour refactor.
9. Reframe deadlift cues to "hip hinge depth" not "back rounding" (7.9). 30-min copy fix.

### P1 — Major quality wins
10. **Switch MediaPipe to GPU delegate** (everywhere). 1-day work + measurement.
11. **Add One Euro Filter** on landmarks (per coordinate, before angles + before render). 1-day implementation, instant visual win.
12. **Per-rep telemetry struct** (`RepRecord`) accumulated into the workout session. 1-day work, unlocks all future analytics.
13. **Voice coach v1** with `AVSpeechSynthesizer` + two profiles. 1-day, gives the personality system a voice.
14. **Tempo decomposition**: concentric ms, eccentric ms, peak velocity. 1-day.
15. **Asymmetry as a first-class metric** (not a fallback). 1-day refactor of `FormFeedbackEngine`.
16. **Spine line + improved overlay** (depth shading, motion trails). 1-day.
17. **Add 5 high-value exercises** (RDL, hip thrust, Bulgarian split squat, reverse lunge, step-up). 2 days total — most are parameter tweaks.

### P2 — Best-in-world investments
18. **Apple Vision 3D fallback** on LiDAR-equipped iPhones. Hybrid pipeline picks best signal per exercise. ~1 week.
19. **Exercise classification** (a small Core ML model that recognizes which of the 30 exercises the user is doing). Removes the menu friction. ~2 weeks.
20. **Voice coach v2** with ElevenLabs streaming, two cloned voices, cue queue with priority + ducking. 1 week.
21. **Range-of-motion personalization.** Calibrate against user's resting joint geometry on first session. ~1 week.
22. **Set-level analytics dashboard:** ROM drift, tempo decay, fatigue curve, asymmetry ramp. UI work, 2 weeks.
23. **Workout replay** with synchronized skeleton overlay + per-rep form scoring. 2 weeks.
24. **Per-user adaptive cooldowns / coaching style** (learn what cues land, suppress what doesn't). ~3 weeks.
25. **Yoga overhaul** — 8+ poses, hold-time scoring, transition detection. ~2 weeks.
26. **A/B harness for thresholds.** Ship two threshold sets to subsets of users; measure rep-count agreement vs hand-counts. ~2 weeks.

### Engineering hygiene (do alongside P0/P1)
- Add a debug HUD: live FPS, inference latency p50/p99, dropped-frame count, per-joint visibility heatmap.
- Add unit tests for `AngleCalculator` (the angle math has zero coverage today and three real bugs).
- Add a recording/replay harness so you can re-run new threshold tunes against canned video.
- Pull `tempoRange`, `minRepDuration`, and `idealAngles` out of code into a JSON config so non-engineers can tune.
- Move `UserProfile.firstName = "Satvik"` into actual user state.

---

## 12 · Two non-obvious strategic notes

### A. Hand-gesture readiness is a feature, but it's also a constraint
Right now the workout-ready flow uses thumbs-up to start. That's clever and works. But it locks both hands away from the exercise position for several seconds. For exercises that start with hands at sides (curls, jumping jacks) it's natural; for exercises that start at the bottom of the rep (push-ups, planks) it's awkward — the user would have to come up just to thumbs-up and then re-position. Consider: hold-an-exercise-pose-for-2-seconds as the "ready" signal, in addition to thumbs-up. The pose detector already has the data.

### B. The engine is one mode away from pivoting into PT
Everything you've built is also the foundation for physical therapy / rehab tracking. Add: range-of-motion baselining over time (knee flexion, shoulder abduction), pain-threshold logging, and a clinician-handoff PDF export. The same skeleton, the same angles, completely different and arguably more defensible market. Worth keeping in mind when you size investments.

---

## 13 · Closing

Spotter is in the top quartile of pose-based fitness apps I've seen. The schema is correct. The cascade is correct. The motivations are right. The biomechanics intent is right.

What's holding it back is a small set of correctness bugs (~2 days of work), an absent voice layer (~1 day for a serviceable v1), an empty telemetry pipeline (~1 day to plumb), and a default-MediaPipe configuration that's leaving real performance on the floor (~1 day to tune).

After that, the work that actually moves you toward "best in the world" is *more exercises spec'd at the squat/push-up level of care*, plus *per-rep analytics* that no current consumer fitness app surfaces well.

The rest is execution.

---

## References

- [MediaPipe Pose Landmarker docs (Google AI Edge)](https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker)
- [BlazePose: On-device Real-time Body Pose Tracking (arXiv)](https://arxiv.org/abs/2006.10204)
- [Knee Flexion/Extension MediaPipe vs Kinovea validation](https://www.researchgate.net/publication/369058814_Knee_FlexionExtension_Angle_Measurement_for_Gait_Analysis_Using_Machine_Learning_Solution_MediaPipe_Pose_and_Its_Comparison_with_Kinovea_R)
- [Accuracy Evaluation of 3D Pose Reconstruction with MediaPipe (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11644880/)
- [Visibility threshold MediaPipe issue #4462](https://github.com/google-ai-edge/mediapipe/issues/4462)
- [MediaPipe pose for sports apps — limitations](https://www.it-jim.com/blog/mediapipe-for-sports-apps/)
- [One Euro Filter (Casiez et al., CHI 2012)](https://gery.casiez.net/1euro/)
- [NSCA Considerations for Squat Depth](https://www.nsca.com/education/articles/nsca-coach/considerations-for-squat-depth/)
- [Deep squat scoping review (Frontiers in Sports)](https://www.frontiersin.org/journals/sports-and-active-living/articles/10.3389/fspor.2024.1477796/full)
- [Knee joint kinetics by squat depth (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC4064719/)
- [Push-up biomechanics & 90° elbow flexion](https://efsupit.ro/images/stories/nr%201%202012/vol%2012_1_%20art%2012.pdf)
- [Push-up vGRF and elbow angle (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC4327800/)
- [Scapulohumeral rhythm and overhead pressing](https://www.synergystrength.ca/blog/2025/4/7/scapulohumeral-rhythm-understanding-shoulder-mechanics-under-load)
- [Glenohumeral & scapular biomechanics review (JOSPT)](https://www.jospt.org/doi/10.2519/jospt.2009.2835)
- [Frontal Plane Projection Angle 2D reliability](https://pubmed.ncbi.nlm.nih.gov/22104115/)
- [FPPA validity for predicting knee moments](https://pmc.ncbi.nlm.nih.gov/articles/PMC9718689/)
- [FPPA vs Dynamic Valgus Index for patellofemoral pain](https://pmc.ncbi.nlm.nih.gov/articles/PMC10324282/)
- [Bicep curl initial vs final ROM hypertrophy (MDPI)](https://www.mdpi.com/2075-4663/11/2/39)
- [Romanian deadlift vs squat vs hip thrust EMG (StrengthLog)](https://www.strengthlog.com/romanian-deadlift-vs-squat-vs-hip-thrust-comparison-of-muscle-activity/)
- [Bulgarian split squat biomechanics (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8136570/)
- [Apple Vision VNDetectHumanBodyPose3DRequest](https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest)
- [WWDC23 — 3D body pose & person segmentation](https://developer.apple.com/videos/play/wwdc2023/111241/)
- [Bird Dog overview (One Peloton)](https://www.onepeloton.com/blog/bird-dog-exercise)
- [Strong core exercises — dead bug, side bridge, bird dog (Jefit)](https://www.jefit.com/wp/exercise-tips/strong-core-exercises-dead-bug-side-bridge-and-bird-dog/)
- [Real-time fitness exercise classification (arXiv)](https://arxiv.org/html/2411.11548v1)
- [Fitcam: detecting and counting repetitive exercises (Springer)](https://link.springer.com/article/10.1186/s40537-024-00915-8)
- [Real-time action scoring for PT (Nature Sci Reports)](https://www.nature.com/articles/s41598-025-29062-7)
- [Plank biomechanics (Physiopedia)](https://www.physio-pedia.com/Plank_exercise)
- [Vision-Based Rep Counting (Medium)](https://medium.com/data-science/vision-based-rep-counting-in-the-wild-cb9a4d1bdb7e)
